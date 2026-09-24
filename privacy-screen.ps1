#requires -Version 5.1
<#
=============================================================================
 隐私屏 (Privacy Screen)
 ----------------------------------------------------------------------------
 场景：人离开宿舍，项目/AI 继续在电脑上跑。锁屏会中断 AI 的截图调试，
      不锁屏屏幕内容会被看到。
 方案：全屏置顶遮罩 + SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)。
      - 物理屏幕上：别人看到的是"系统维护中"遮罩（看不到你的桌面）；
      - 软件截图里：Windows 会把遮罩从所有截图/录屏中剔除，
        AI 截图看到的是遮罩背后的真实桌面，调试不受影响；
      - 鼠标点击穿透遮罩（AI 的键鼠自动化不受影响）。
      - 设置 -Password 后，遮罩显示时直接键入密码即可静默解锁：
        全程无任何提示，且会吞掉真人按键（密码不会打进你的项目）；
        AI 的注入式键盘输入则被放行，调试不受影响。
       - 默认屏蔽真人鼠标/触控板（-BlockMouse），AI 注入的鼠标输入放行。
       - 默认开启防烧屏（-AntiBurn）：文字/画面每 20 秒轻微漂移 + 背景亮度微变。
       - -HideConsole 可隐藏控制台窗口（配合 启动-静默.cmd 可完全无窗口运行）。

 用法示例：
   powershell -NoProfile -ExecutionPolicy Bypass -File .\privacy-screen.ps1
   powershell -NoProfile -ExecutionPolicy Bypass -File .\privacy-screen.ps1 -HideConsole
   powershell -NoProfile -ExecutionPolicy Bypass -File .\privacy-screen.ps1 -BlockMouse:$false
   powershell -NoProfile -ExecutionPolicy Bypass -File .\privacy-screen.ps1 -AntiBurn:$false
   powershell -NoProfile -ExecutionPolicy Bypass -File .\privacy-screen.ps1 -Password 1234
   powershell -NoProfile -ExecutionPolicy Bypass -File .\privacy-screen.ps1 -Password ''
   powershell -NoProfile -ExecutionPolicy Bypass -File .\privacy-screen.ps1 -Mode lockstyle
   powershell -NoProfile -ExecutionPolicy Bypass -File .\privacy-screen.ps1 -Mode image -ImagePath C:\wall.jpg
   powershell -NoProfile -ExecutionPolicy Bypass -File .\privacy-screen.ps1 -Text '正在跑实验|请勿动电脑|回来找我'
   powershell -NoProfile -ExecutionPolicy Bypass -File .\privacy-screen.ps1 -ScreenOff -DimBrightness
   powershell -NoProfile -ExecutionPolicy Bypass -File .\privacy-screen.ps1 -SelfTest
   powershell -NoProfile -ExecutionPolicy Bypass -File .\privacy-screen.ps1 -CompileOnly

 退出：托盘图标右键"退出"；紧急时 Ctrl+Alt+Del -> 任务管理器结束 powershell。
 建议先用 selfcheck.ps1 实测你机器上 AI 用的截图路径是否豁免成功。
 需要 Windows 10 2004 (build 19041) 及以上。
=============================================================================
#>

[CmdletBinding()]
param(
    [ValidateSet('maintenance', 'black', 'image', 'lockstyle')]
    [string]$Mode = 'maintenance',

    [string]$ImagePath = '',

    [string]$Text = '',

    [string]$Password = '1234',

    [string]$Hotkey = 'Ctrl+Shift+Alt+F12',

    [switch]$ScreenOff,
    [switch]$DimBrightness,
    [switch]$EatClicks,
    [switch]$StartHidden,
    [switch]$SelfTest,
    [switch]$CompileOnly,
    [switch]$HideConsole,
    [switch]$FixTouchpad,
    [switch]$ScanRemote,
    [switch]$Replace,
    [switch]$SetupTouchpadDevice,
    [switch]$RemoveTouchpadDevice,
    [ValidateSet('auto', 'registry', 'device', 'off')]
    [string]$TouchpadMode = 'auto',
    [string]$TouchpadInstanceId = '',
    [bool]$BlockMouse = $true,
    [bool]$BlockTouchpad = $true,
    [bool]$AntiBurn = $true,
    [bool]$RemoteDetect = $true,
    [bool]$RemoteHideOverlay = $true,
    [int]$RemoteEndDelaySec = 15,
    [string]$RemoteProcesses = 'AweSun,awesun_guard,SunloginClient,SunloginRemote',
    [int]$DemoMs = 0
)

$ErrorActionPreference = 'Stop'

$src = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

public static class Native
{
    public const uint WDA_NONE = 0;
    public const uint WDA_MONITOR = 1;
    public const uint WDA_EXCLUDEFROMCAPTURE = 0x11;

    public const int WM_HOTKEY = 0x0312;
    public const int WM_SYSCOMMAND = 0x0112;
    public const int SC_MONITORPOWER = 0xF170;

    public const int WS_EX_TOPMOST = 0x00000008;
    public const int WS_EX_TRANSPARENT = 0x00000020;
    public const int WS_EX_TOOLWINDOW = 0x00000080;
    public const int WS_EX_NOACTIVATE = 0x08000000;

    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

    [DllImport("user32.dll")]
    public static extern bool SetWindowDisplayAffinity(IntPtr hWnd, uint dwAffinity);

    [DllImport("user32.dll")]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll")]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll")]
    public static extern IntPtr SetWindowsHookEx(int idHook, LowLevelMouseProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll")]
    public static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    public static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    public delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    public delegate IntPtr LowLevelMouseProc(int nCode, IntPtr wParam, IntPtr lParam);

    public const int WH_KEYBOARD_LL = 13;
    public const int WH_MOUSE_LL = 14;
    public const int WM_KEYDOWN = 0x0100;
    public const int WM_KEYUP = 0x0101;
    public const int WM_SYSKEYDOWN = 0x0104;
    public const int WM_SYSKEYUP = 0x0105;
    public const uint LLKHF_INJECTED = 0x10;
    public const uint LLMHF_INJECTED = 0x01;

    [StructLayout(LayoutKind.Sequential)]
    public struct KBDLLHOOKSTRUCT
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MSLLHOOKSTRUCT
    {
        public int ptX;
        public int ptY;
        public uint mouseData;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    public const int SPI_GETDESKWALLPAPER = 0x0073;

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool SystemParametersInfo(int uiAction, int uiParam, StringBuilder pvParam, int fWinIni);

    public const int WM_SETTINGCHANGE = 0x001A;
    public const uint SMTO_ABORTIFHUNG = 0x0002;

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, int msg, IntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);

    // 远程会话检测用
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc proc, IntPtr data);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr data);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder text, int max);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int max);

    public const int AF_INET = 2;
    public const int TCP_TABLE_OWNER_PID_ALL = 5;

    [DllImport("iphlpapi.dll", SetLastError = true)]
    public static extern uint GetExtendedTcpTable(IntPtr pTcpTable, ref int pdwSize, bool bOrder, int ulAf, int tableClass, uint reserved);

    [StructLayout(LayoutKind.Sequential)]
    public struct MIB_TCPROW_OWNER_PID
    {
        public uint state;
        public uint localAddr;
        public uint localPort;
        public uint remoteAddr;
        public uint remotePort;
        public uint owningPid;
    }

    // 查询设备节点真实状态（用来确认"触控板到底禁用成功没有"）
    [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)]
    public static extern int CM_Locate_DevNodeW(out uint pdnDevInst, string pDeviceID, uint ulFlags);

    [DllImport("cfgmgr32.dll")]
    public static extern int CM_Get_DevNode_Status(out uint pulStatus, out uint pulProblemNumber, uint dnDevInst, uint ulFlags);

    [DllImport("user32.dll")]
    public static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonitorEnumProc proc, IntPtr data);

    public delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdc, ref NativeRect rect, IntPtr data);

    [StructLayout(LayoutKind.Sequential)]
    public struct NativeRect
    {
        public int left;
        public int top;
        public int right;
        public int bottom;
    }

    [DllImport("dxva2.dll", EntryPoint = "GetNumberOfPhysicalMonitorsFromHMONITOR")]
    public static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, ref uint count);

    [DllImport("dxva2.dll", EntryPoint = "GetPhysicalMonitorsFromHMONITOR")]
    public static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr hMonitor, uint dwPhysicalMonitorArraySize, [Out] PhysicalMonitor[] pPhysicalMonitorArray);

    [DllImport("dxva2.dll", EntryPoint = "SetMonitorBrightness")]
    public static extern bool SetMonitorBrightness(IntPtr hMonitor, uint dwNewBrightness);

    [DllImport("dxva2.dll", EntryPoint = "GetMonitorBrightness")]
    public static extern bool GetMonitorBrightness(IntPtr hMonitor, ref uint pdwMinimumBrightness, ref uint pdwCurrentBrightness, ref uint pdwMaximumBrightness);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct PhysicalMonitor
    {
        public IntPtr hPhysicalMonitor;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szPhysicalMonitorDescription;
    }
}

public class OverlayForm : Form
{
    private string _mode;
    private bool _eatClicks;
    private string _customText;
    private bool _antiBurn;
    private Image _image;
    private Panel _bg;
    private Label _label;
    private System.Windows.Forms.Timer _timer;
    private System.Windows.Forms.Timer _driftTimer;
    private int _progress;
    private int _driftIndex;

    private static readonly int[,] DriftOffsets = new int[,] {
        {0,0}, {3,2}, {-2,4}, {4,-3}, {-4,-2}, {2,-4}, {-3,3}, {5,0}, {0,5}, {-5,0}, {0,-5}, {1,1}
    };

    private static readonly Color[] BgShades = new Color[] {
        Color.FromArgb(9, 12, 16), Color.FromArgb(11, 14, 19), Color.FromArgb(8, 11, 14),
        Color.FromArgb(12, 16, 21), Color.FromArgb(10, 13, 17)
    };

    public OverlayForm(Rectangle bounds, string mode, string imagePath, bool eatClicks, string customText, bool antiBurn)
    {
        _mode = mode;
        _eatClicks = eatClicks;
        _customText = NormalizeText(customText);
        _antiBurn = antiBurn;
        Bounds = bounds;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;
        BackColor = BgShades[0];
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);

        string imgPath = imagePath;
        if (string.IsNullOrEmpty(imgPath) && mode == "lockstyle") imgPath = GetCurrentWallpaper();
        try
        {
            if (!string.IsNullOrEmpty(imgPath) && File.Exists(imgPath)) _image = Image.FromFile(imgPath);
        }
        catch { }

        Control host = this;
        if (_image != null)
        {
            _bg = new Panel();
            _bg.BackColor = BackColor;
            _bg.BackgroundImage = _image;
            _bg.BackgroundImageLayout = ImageLayout.Stretch;
            _bg.Location = new Point(-8, -8);
            _bg.Size = new Size(ClientSize.Width + 16, ClientSize.Height + 16);
            Controls.Add(_bg);
            host = _bg;
        }

        if (mode == "lockstyle")
        {
            _label = MakeLabel(34f, true, Color.FromArgb(232, 236, 240));
            host.Controls.Add(_label);
            _timer = new System.Windows.Forms.Timer();
            _timer.Interval = 1000;
            _timer.Tick += delegate { UpdateText(); };
            _timer.Start();
            UpdateText();
        }
        else if (!string.IsNullOrEmpty(_customText))
        {
            _label = MakeLabel(26f, false, Color.FromArgb(232, 236, 240));
            _label.Text = _customText;
            host.Controls.Add(_label);
        }
        else if (mode == "maintenance")
        {
            _label = MakeLabel(26f, false, Color.FromArgb(232, 236, 240));
            host.Controls.Add(_label);
            _progress = 7;
            _timer = new System.Windows.Forms.Timer();
            _timer.Interval = 900;
            _timer.Tick += delegate { UpdateText(); };
            _timer.Start();
            UpdateText();
        }

        if (_antiBurn)
        {
            _driftTimer = new System.Windows.Forms.Timer();
            _driftTimer.Interval = 20000;
            _driftTimer.Tick += delegate { Drift(); };
            _driftTimer.Start();
        }
    }

    // 防烧屏：文字/画面每隔一段时间轻微位移，背景亮度微变
    private void Drift()
    {
        _driftIndex = (_driftIndex + 1) % (DriftOffsets.Length / 2);
        int dx = DriftOffsets[_driftIndex, 0];
        int dy = DriftOffsets[_driftIndex, 1];
        if (_label != null) _label.Padding = new Padding(dx * 2, dy * 2, 0, 0);
        if (_bg != null) _bg.Location = new Point(-8 + dx, -8 + dy);
        BackColor = BgShades[_driftIndex % BgShades.Length];
        if (_bg != null) _bg.BackColor = BackColor;
        Invalidate(true);
    }

    private static string GetCurrentWallpaper()
    {
        try
        {
            StringBuilder sb = new StringBuilder(1024);
            if (Native.SystemParametersInfo(Native.SPI_GETDESKWALLPAPER, sb.Capacity, sb, 0))
            {
                string p = sb.ToString();
                if (!string.IsNullOrEmpty(p) && File.Exists(p)) return p;
            }
        }
        catch { }
        return "";
    }

    private static string NormalizeText(string s)
    {
        if (string.IsNullOrEmpty(s)) return s;
        return s.Replace("\\r\\n", "\r\n").Replace("\\n", "\r\n").Replace("|", "\r\n");
    }

    private Label MakeLabel(float size, bool bold, Color color)
    {
        Label l = new Label();
        l.Dock = DockStyle.Fill;
        l.TextAlign = ContentAlignment.MiddleCenter;
        l.BackColor = Color.Transparent;
        l.ForeColor = color;
        try { l.Font = new Font("Microsoft YaHei UI", size, bold ? FontStyle.Bold : FontStyle.Regular); }
        catch { l.Font = new Font(FontFamily.GenericSansSerif, size); }
        return l;
    }

    private void UpdateText()
    {
        if (_label == null) return;
        if (_mode == "lockstyle")
        {
            DateTime n = DateTime.Now;
            string s = n.ToString("HH:mm:ss") + "\r\n" + n.ToString("yyyy年M月d日 dddd") + "\r\n\r\n";
            s += string.IsNullOrEmpty(_customText) ? "已锁定 · 请勿操作" : _customText;
            _label.Text = s;
        }
        else
        {
            _progress += 3;
            if (_progress > 98) _progress = 8;
            _label.Text = "系统维护中 · 请勿操作\r\n\r\n后台任务正在运行\r\n请勿触碰键盘与鼠标\r\n\r\n维护进度 " + _progress + "%";
        }
    }

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= Native.WS_EX_TOPMOST | Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE;
            if (!_eatClicks) cp.ExStyle |= Native.WS_EX_TRANSPARENT;
            return cp;
        }
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        bool ok = Native.SetWindowDisplayAffinity(Handle, Native.WDA_EXCLUDEFROMCAPTURE);
        if (!ok)
        {
            Native.SetWindowDisplayAffinity(Handle, Native.WDA_MONITOR);
        }
    }
}

public class InputBlocker : IDisposable
{
    private IntPtr _kbHook = IntPtr.Zero;
    private IntPtr _mouseHook = IntPtr.Zero;
    private Native.LowLevelKeyboardProc _kbProc;
    private Native.LowLevelMouseProc _mouseProc;
    private string _password;
    private string _buffer = "";
    private Action _onUnlock;
    private Action _onRemoteToggle;
    private bool _ctrl = false, _shift = false, _alt = false;

    public bool KeyboardInstalled { get { return _kbHook != IntPtr.Zero; } }
    public bool MouseInstalled { get { return _mouseHook != IntPtr.Zero; } }

    // true = 放行模式（远程控制期间）：不吞输入，但密码检测仍然工作
    public bool PassThrough = false;

    // 远程模式热键：默认 Ctrl+Shift+Alt+R，在钩子内部处理，所以被屏蔽时也有效
    public uint RemoteHotkeyVk = 0x52; // R

    public InputBlocker(string password, bool blockMouse, Action onUnlock, Action onRemoteToggle)
    {
        _password = password == null ? "" : password;
        _onUnlock = onUnlock;
        _onRemoteToggle = onRemoteToggle;
        _kbProc = KbProc;
        _kbHook = Native.SetWindowsHookEx(Native.WH_KEYBOARD_LL, _kbProc, IntPtr.Zero, 0);
        if (blockMouse && _kbHook != IntPtr.Zero)
        {
            _mouseProc = MouseProc;
            _mouseHook = Native.SetWindowsHookEx(Native.WH_MOUSE_LL, _mouseProc, IntPtr.Zero, 0);
        }
    }

    private IntPtr KbProc(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            int msg = (int)wParam;
            if (msg == Native.WM_KEYDOWN || msg == Native.WM_SYSKEYDOWN ||
                msg == Native.WM_KEYUP || msg == Native.WM_SYSKEYUP)
            {
                Native.KBDLLHOOKSTRUCT k = (Native.KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(Native.KBDLLHOOKSTRUCT));
                bool injected = (k.flags & Native.LLKHF_INJECTED) != 0;
                bool down = (msg == Native.WM_KEYDOWN || msg == Native.WM_SYSKEYDOWN);

                if (down)
                {
                    TrackModifiers(k.vkCode, true);
                    // 远程模式热键（真人和远程输入都算，注入输入不算）
                    if (!injected && k.vkCode == RemoteHotkeyVk && _ctrl && _shift && _alt)
                    {
                        if (_onRemoteToggle != null) _onRemoteToggle();
                        return (IntPtr)1;
                    }
                    // 密码缓冲：屏蔽状态只计真人按键；放行状态（远程控制中）计入所有按键，便于远程打字解锁
                    if (!injected || PassThrough)
                    {
                        char? c = KeyToChar(k.vkCode);
                        if (c.HasValue)
                        {
                            _buffer += c.Value;
                            int n = _password.Length;
                            if (n > 0 && _buffer.Length > n) _buffer = _buffer.Substring(_buffer.Length - n);
                            if (_buffer == _password && n > 0)
                            {
                                _buffer = "";
                                if (_onUnlock != null) _onUnlock();
                            }
                        }
                    }
                }
                else
                {
                    TrackModifiers(k.vkCode, false);
                }

                // Num Lock 放行（不屏蔽数字键盘锁开关）
                if (!injected && !PassThrough && k.vkCode == 0x90)
                    return Native.CallNextHookEx(_kbHook, nCode, wParam, lParam);
                if (!injected && !PassThrough) return (IntPtr)1; // 屏蔽真人按键，全程无反馈
            }
        }
        return Native.CallNextHookEx(_kbHook, nCode, wParam, lParam);
    }

    private void TrackModifiers(uint vk, bool down)
    {
        if (vk == 0x11 || vk == 0xA2 || vk == 0xA3) _ctrl = down;
        else if (vk == 0x10 || vk == 0xA0 || vk == 0xA1) _shift = down;
        else if (vk == 0x12 || vk == 0xA4 || vk == 0xA5) _alt = down;
    }

    private IntPtr MouseProc(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            Native.MSLLHOOKSTRUCT m = (Native.MSLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(Native.MSLLHOOKSTRUCT));
            if ((m.flags & Native.LLMHF_INJECTED) == 0 && !PassThrough)
            {
                return (IntPtr)1; // 吞掉真人鼠标/触控板（移动、点击、滚轮）
            }
        }
        return Native.CallNextHookEx(_mouseHook, nCode, wParam, lParam);
    }

    private static char? KeyToChar(uint vk)
    {
        if (vk >= 0x30 && vk <= 0x39) return (char)('0' + (vk - 0x30));
        if (vk >= 0x41 && vk <= 0x5A) return (char)('a' + (vk - 0x41));
        if (vk >= 0x60 && vk <= 0x69) return (char)('0' + (vk - 0x60));
        return null;
    }

    public void UpdatePassword(string newPassword)
    {
        _password = newPassword == null ? "" : newPassword;
        _buffer = "";
    }

    public void Dispose()
    {
        if (_mouseHook != IntPtr.Zero)
        {
            Native.UnhookWindowsHookEx(_mouseHook);
            _mouseHook = IntPtr.Zero;
        }
        if (_kbHook != IntPtr.Zero)
        {
            Native.UnhookWindowsHookEx(_kbHook);
            _kbHook = IntPtr.Zero;
        }
    }
}

// 精密触控板总开关（HKCU，无需管理员）。
// 三指/四指手势由系统手势引擎处理，不经过键鼠钩子，只能靠这个开关关闭整个触控板。
public static class Touchpad
{
    private const string StatusPath = @"Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad\Status";
    private const string RootPath = @"Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad";

    private static bool _saved = false;
    private static int _savedValue = 1;

    private static readonly string[] GestureValues = new string[] {
        "ThreeFingerSlideEnabled", "ThreeFingerTapEnabled",
        "FourFingerSlideEnabled", "FourFingerTapEnabled"
    };

    private static Dictionary<string, object> _savedGestures = new Dictionary<string, object>();

    public static bool Available
    {
        get
        {
            try
            {
                using (RegistryKey k = Registry.CurrentUser.OpenSubKey(StatusPath, false)) return k != null;
            }
            catch { return false; }
        }
    }

    // 关闭整个精密触控板；同时把三指/四指手势开关写 0（双保险，防总开关不是实时生效）
    public static bool Disable()
    {
        bool ok = false;
        try
        {
            using (RegistryKey k = Registry.CurrentUser.OpenSubKey(StatusPath, true))
            {
                if (k != null)
                {
                    object v = k.GetValue("Enabled");
                    if (v != null) { _savedValue = Convert.ToInt32(v); _saved = true; }
                    k.SetValue("Enabled", 0, RegistryValueKind.DWord);
                    ok = true;
                }
            }
        }
        catch { }

        try
        {
            using (RegistryKey k = Registry.CurrentUser.OpenSubKey(RootPath, true))
            {
                if (k != null)
                {
                    _savedGestures.Clear();
                    foreach (string name in GestureValues)
                    {
                        object old = k.GetValue(name);
                        if (old != null) _savedGestures[name] = old;
                        k.SetValue(name, 0, RegistryValueKind.DWord);
                    }
                    ok = true;
                }
            }
        }
        catch { }

        if (ok) Broadcast();
        return ok;
    }

    public static void Restore()
    {
        try
        {
            using (RegistryKey k = Registry.CurrentUser.OpenSubKey(StatusPath, true))
            {
                if (k != null) k.SetValue("Enabled", _saved ? _savedValue : 1, RegistryValueKind.DWord);
            }
            _saved = false;
        }
        catch { }

        try
        {
            using (RegistryKey k = Registry.CurrentUser.OpenSubKey(RootPath, true))
            {
                if (k != null)
                {
                    foreach (string name in GestureValues)
                    {
                        if (_savedGestures.ContainsKey(name)) k.SetValue(name, _savedGestures[name]);
                        else k.DeleteValue(name, false);
                    }
                }
            }
            _savedGestures.Clear();
        }
        catch { }

        Broadcast();
    }

    private static void Broadcast()
    {
        try
        {
            IntPtr result;
            Native.SendMessageTimeout((IntPtr)0xFFFF, Native.WM_SETTINGCHANGE, IntPtr.Zero, RootPath, Native.SMTO_ABORTIFHUNG, 1000, out result);
        }
        catch { }
    }

    // ---------- 设备级禁用（注册表开关对手势无效时的正解）----------
    // 一次性用管理员权限建好两个计划任务（禁用/启用触控板），运行时用 schtasks /run 触发，无需再提权。

    public static string DeviceIdFile = "";
    public static string DeviceId = "";
    public static bool UseDeviceMode = false;

    public static bool DeviceModeConfigured()
    {
        try
        {
            return !string.IsNullOrEmpty(DeviceIdFile) && File.Exists(DeviceIdFile);
        }
        catch { return false; }
    }

    // 真实查询设备节点状态：usable=true 表示设备正常工作
    public static bool DeviceUsable(out string detail)
    {
        detail = "";
        uint devInst;
        int hr = Native.CM_Locate_DevNodeW(out devInst, DeviceId, 0);
        if (hr != 0) { detail = "找不到设备节点 hr=" + hr; return false; }
        uint status, problem;
        hr = Native.CM_Get_DevNode_Status(out status, out problem, devInst, 0);
        if (hr != 0) { detail = "查询状态失败 hr=" + hr; return false; }
        bool hasProblem = (status & 0x00000400) != 0; // DN_HAS_PROBLEM
        detail = "status=0x" + status.ToString("X") + " problem=" + problem;
        return !hasProblem;
    }

    // 触发任务并等待设备状态真正变化（schtasks 返回成功不代表 pnputil 生效）
    private static bool DeviceAct(string task, bool wantUsable)
    {
        RunTask(task);
        for (int i = 0; i < 20; i++)
        {
            string detail;
            bool usable = DeviceUsable(out detail);
            if (usable == wantUsable) return true;
            Thread.Sleep(400);
        }
        return false;
    }

    public static bool DeviceDisable() { return DeviceAct("PrivacyScreen-TouchpadOff", false); }
    public static bool DeviceEnable() { return DeviceAct("PrivacyScreen-TouchpadOn", true); }

    private static bool RunTask(string name)
    {
        try
        {
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "schtasks.exe");
            psi.Arguments = "/run /tn \"" + name + "\"";
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            Process p = Process.Start(psi);
            p.WaitForExit(8000);
            return p.ExitCode == 0;
        }
        catch { return false; }
    }
}

// 远程控制会话检测（向日葵 / AweSun / SunloginClient 等）
// 空闲时远程工具会常驻 1~2 条到服务器的 TCP 连接，所以"有连接"不能作为判据；
// 判据用：远程工具出现了可见的顶层窗口（被控时的提示条/主窗口），空闲时它全部缩在托盘(不可见)。
public static class RemoteSession
{
    public static string ProcessList = "AweSun,awesun_guard,SunloginClient,SunloginRemote";

    private static string[] Names()
    {
        List<string> list = new List<string>();
        foreach (string s in ProcessList.Split(','))
        {
            string t = s.Trim();
            if (t.Length > 0) list.Add(t);
        }
        return list.ToArray();
    }

    public static List<int> ToolPids()
    {
        List<int> pids = new List<int>();
        foreach (string name in Names())
        {
            try
            {
                Process[] arr = Process.GetProcessesByName(name);
                foreach (Process p in arr)
                {
                    try { pids.Add(p.Id); } catch { }
                    try { p.Dispose(); } catch { }
                }
            }
            catch { }
        }
        return pids;
    }

    private static List<string> WindowList(List<int> pids, bool onlyVisible)
    {
        List<string> res = new List<string>();
        if (pids.Count == 0) return res;
        Native.EnumWindows(delegate(IntPtr h, IntPtr data)
        {
            uint pid;
            Native.GetWindowThreadProcessId(h, out pid);
            if (!pids.Contains((int)pid)) return true;
            bool vis = Native.IsWindowVisible(h);
            if (onlyVisible && !vis) return true;
            StringBuilder cls = new StringBuilder(256);
            Native.GetClassName(h, cls, 256);
            StringBuilder title = new StringBuilder(256);
            Native.GetWindowText(h, title, 256);
            res.Add("pid=" + pid + " visible=" + vis + " class='" + cls.ToString() + "' title='" + title.ToString() + "'");
            return true;
        }, IntPtr.Zero);
        return res;
    }

    public static List<string> EstablishedRemote(List<int> pids, out int count)
    {
        count = 0;
        List<string> res = new List<string>();
        if (pids.Count == 0) return res;
        try
        {
            int size = 0;
            Native.GetExtendedTcpTable(IntPtr.Zero, ref size, false, Native.AF_INET, Native.TCP_TABLE_OWNER_PID_ALL, 0);
            if (size <= 0) return res;
            IntPtr buf = Marshal.AllocHGlobal(size);
            try
            {
                if (Native.GetExtendedTcpTable(buf, ref size, false, Native.AF_INET, Native.TCP_TABLE_OWNER_PID_ALL, 0) != 0) return res;
                int rows = Marshal.ReadInt32(buf);
                int rowSize = Marshal.SizeOf(typeof(Native.MIB_TCPROW_OWNER_PID));
                long baseAddr = buf.ToInt64() + 4;
                for (int i = 0; i < rows; i++)
                {
                    Native.MIB_TCPROW_OWNER_PID row = (Native.MIB_TCPROW_OWNER_PID)Marshal.PtrToStructure(
                        new IntPtr(baseAddr + i * rowSize), typeof(Native.MIB_TCPROW_OWNER_PID));
                    if (row.state != 5) continue; // ESTABLISHED
                    if (!pids.Contains((int)row.owningPid)) continue;
                    uint ra = row.remoteAddr;
                    int b1 = (int)(ra & 0xFF), b2 = (int)((ra >> 8) & 0xFF), b3 = (int)((ra >> 16) & 0xFF), b4 = (int)((ra >> 24) & 0xFF);
                    if (b1 == 127) continue; // 回环不算
                    int port = (int)(((row.remotePort & 0xFF) << 8) | ((row.remotePort >> 8) & 0xFF));
                    count++;
                    res.Add("pid=" + row.owningPid + " -> " + b1 + "." + b2 + "." + b3 + "." + b4 + ":" + port);
                }
            }
            finally { Marshal.FreeHGlobal(buf); }
        }
        catch { }
        return res;
    }

    public static bool IsActive(out string why)
    {
        why = "";
        List<int> pids = ToolPids();
        if (pids.Count == 0) { why = "远程控制工具未运行"; return false; }
        List<string> vis = WindowList(pids, true);
        if (vis.Count > 0)
        {
            why = "检测到远程工具可见窗口 -> " + vis[0] + (vis.Count > 1 ? "（共" + vis.Count + "个）" : "");
            return true;
        }
        int connCount;
        EstablishedRemote(pids, out connCount);
        why = "远程工具在运行但无可见窗口（连接数 " + connCount + "，属空闲常驻）";
        return false;
    }

    public static string Scan()
    {
        StringBuilder sb = new StringBuilder();
        List<int> pids = ToolPids();
        sb.AppendLine("远程工具进程名配置 : " + ProcessList);
        sb.AppendLine("匹配到的 PID       : " + (pids.Count == 0 ? "(无)" : string.Join(", ", pids.ConvertAll(delegate(int p) { return p.ToString(); }).ToArray())));
        sb.AppendLine("");
        List<string> all = WindowList(pids, false);
        sb.AppendLine("远程工具的全部顶层窗口（含隐藏）: " + all.Count + " 个");
        foreach (string w in all) sb.AppendLine("  " + w);
        sb.AppendLine("");
        List<string> vis = WindowList(pids, true);
        sb.AppendLine("其中【可见】窗口: " + vis.Count + " 个   <-- 这是判定被控的依据");
        foreach (string w in vis) sb.AppendLine("  " + w);
        sb.AppendLine("");
        int connCount;
        List<string> conns = EstablishedRemote(pids, out connCount);
        sb.AppendLine("非回环已建立 TCP 连接: " + connCount + " 条（空闲时也有，仅作参考）");
        foreach (string c in conns) sb.AppendLine("  " + c);
        sb.AppendLine("");
        string why;
        bool active = IsActive(out why);
        sb.AppendLine("判定: " + (active ? "【正在被远程控制】" : "【未在控制中】") + "  " + why);
        return sb.ToString();
    }
}

public class HotkeyHost : NativeWindow
{
    private Action _action;

    public HotkeyHost(Action action)
    {
        _action = action;
        CreateHandle(new CreateParams());
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == Native.WM_HOTKEY && (int)m.WParam == 1 && _action != null)
        {
            _action();
        }
        base.WndProc(ref m);
    }
}

public static class HotkeyParser
{
    public static bool TryParse(string spec, out uint mods, out uint vk)
    {
        mods = 0; vk = 0;
        if (string.IsNullOrEmpty(spec)) return false;
        string[] parts = spec.Split('+');
        foreach (string raw in parts)
        {
            string t = raw.Trim().ToLowerInvariant();
            if (t.Length == 0) continue;
            if (t == "ctrl" || t == "control") { mods |= 0x2; continue; }
            if (t == "shift") { mods |= 0x4; continue; }
            if (t == "alt") { mods |= 0x1; continue; }
            if (t == "win") { mods |= 0x8; continue; }
            uint k = 0;
            if (t.Length >= 2 && t[0] == 'f')
            {
                int n = 0;
                if (int.TryParse(t.Substring(1), out n) && n >= 1 && n <= 24) k = (uint)(0x70 + n - 1);
            }
            if (k == 0)
            {
                switch (t)
                {
                    case "esc": case "escape": k = 0x1B; break;
                    case "space": k = 0x20; break;
                    case "pause": k = 0x13; break;
                    case "home": k = 0x24; break;
                    case "end": k = 0x23; break;
                    case "insert": k = 0x2D; break;
                    case "delete": k = 0x2E; break;
                    case "pageup": k = 0x21; break;
                    case "pagedown": k = 0x22; break;
                    case "up": k = 0x26; break;
                    case "down": k = 0x28; break;
                    case "left": k = 0x25; break;
                    case "right": k = 0x27; break;
                    default:
                        if (t.Length == 1)
                        {
                            char c = t[0];
                            if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) k = (uint)char.ToUpperInvariant(c);
                        }
                        break;
                }
            }
            if (k == 0) return false;
            vk = k;
        }
        if (mods == 0 || vk == 0) return false;
        return true;
    }
}

public static class PrivacyEngine
{
    public static string Mode = "maintenance";
    public static string ImagePath = "";
    public static string CustomText = "";
    public static string Password = "";
    public static string Hotkey = "Ctrl+Shift+Alt+F12";
    public static string AppDir = "";
    public static bool ScreenOff = false;
    public static bool DimBrightness = false;
    public static bool EatClicks = false;
    public static bool BlockMouse = true;
    public static bool BlockTouchpad = true;
    public static bool AntiBurn = true;
    public static bool RemoteDetect = true;
    public static bool RemoteHideOverlay = true;
    public static int RemoteEndPolls = 10;
    public static string RemoteProcesses = "AweSun,awesun_guard,SunloginClient,SunloginRemote";

    private static System.Windows.Forms.Timer _remoteTimer;
    private static bool _remoteActive = false;
    private static bool _remoteForced = false;
    private static bool _hiddenByRemote = false;
    private static int _inactiveStreak = 0;
    private static bool? _antiBurnBeforeScreenOff = null;
    private static bool? _dimBrightnessBeforeScreenOff = null;

    private static List<OverlayForm> _overlays = new List<OverlayForm>();
    private static List<object[]> _brightness = new List<object[]>();
    private static NotifyIcon _tray;
    private static HotkeyHost _hotkeyHost;
    private static InputBlocker _inputBlocker;
    private static Mutex _mutex;

    public static bool IsShown { get { return _overlays.Count > 0; } }

    public static string LogPath = "";

    public static void Log(string msg)
    {
        try { Console.WriteLine("[隐私屏] " + msg); } catch { }
        try
        {
            if (!string.IsNullOrEmpty(LogPath))
            {
                File.AppendAllText(LogPath, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + msg + "\r\n", Encoding.UTF8);
            }
        }
        catch { }
    }

    public static bool TryAcquireSingleInstance()
    {
        bool createdNew;
        _mutex = new Mutex(true, "Local\\PrivacyScreenOverlay_7c91e3", out createdNew);
        return createdNew;
    }

    public static void Start(bool startHidden)
    {
        Application.EnableVisualStyles();
        // 进程退出兜底：无论怎么退出，都把触控板恢复回来
        AppDomain.CurrentDomain.ProcessExit += delegate
        {
            if (Touchpad.UseDeviceMode && Touchpad.DeviceModeConfigured()) Touchpad.DeviceEnable();
            else Touchpad.Restore();
        };
        SetupTray();
        SetupHotkey(Hotkey);
        StartRemoteWatch();
        if (!startHidden) Show();
        Application.Run();
    }

    // ---------- 远程控制会话检测：被控时放行鼠标键盘，断开后恢复屏蔽 ----------

    private static void StartRemoteWatch()
    {
        if (!RemoteDetect) return;
        RemoteSession.ProcessList = RemoteProcesses;
        _remoteTimer = new System.Windows.Forms.Timer();
        _remoteTimer.Interval = 1500;
        _remoteTimer.Tick += delegate { PollRemote(); };
        _remoteTimer.Start();
        Log("远程控制检测已开启（进程名：" + RemoteProcesses + "；动作：" + (RemoteHideOverlay ? "被控时收起遮罩" : "被控时放行输入")
            + "；手动切换热键 Ctrl+Shift+Alt+R）。");
        PollRemote();
    }

    private static void PollRemote()
    {
        bool detected = false;
        string why = "";
        try { detected = RemoteSession.IsActive(out why); }
        catch (Exception ex) { why = "检测异常：" + ex.Message; }

        if (_remoteForced || detected)
        {
            _inactiveStreak = 0;
            ApplyRemoteState(true, _remoteForced ? "手动切换到远程模式（热键）" : why);
            return;
        }

        // 消抖：判据短暂消失（例如被控提示条窗口自动隐藏）不立即恢复，连续 N 次无信号才算结束
        if (!_remoteActive) return;
        _inactiveStreak++;
        if (_inactiveStreak >= RemoteEndPolls)
        {
            _inactiveStreak = 0;
            ApplyRemoteState(false, why);
        }
    }

    // 由键盘钩子内部调用（被屏蔽时热键依然有效）
    public static void ToggleRemoteMode()
    {
        _remoteForced = !_remoteForced;
        if (_remoteForced)
        {
            Log("收到热键：切换为远程模式。");
            PollRemote();
        }
        else
        {
            Log("收到热键：退出远程模式，恢复自动检测。");
            _inactiveStreak = RemoteEndPolls;
            ApplyRemoteState(false, "手动退出远程模式（热键）");
        }
    }

    private static void ApplyRemoteState(bool active, string why)
    {
        if (active == _remoteActive) return;
        _remoteActive = active;

        if (RemoteHideOverlay)
        {
            if (active)
            {
                if (IsShown)
                {
                    _hiddenByRemote = true;
                    Log("检测到远程控制 -> 收起遮罩（远控可看到真实画面，输入与触控板同时恢复）。原因：" + why);
                    Hide();
                }
                else
                {
                    Log("检测到远程控制（遮罩本来就未显示）。原因：" + why);
                }
            }
            else if (_hiddenByRemote)
            {
                _hiddenByRemote = false;
                Log("远程控制已结束 -> 重新盖上遮罩并恢复屏蔽。原因：" + why);
                Show();
            }
            else
            {
                Log("远程控制已结束（遮罩不是被本功能收起的，保持原状）。原因：" + why);
            }
            return;
        }

        if (_inputBlocker != null) _inputBlocker.PassThrough = active;
        if (active)
        {
            Log("检测到远程控制在操作 -> 已放行鼠标键盘（遮罩仍在，密码仍可解锁）。原因：" + why);
        }
        else
        {
            Log("远程控制已结束 -> 已恢复屏蔽鼠标键盘。原因：" + why);
        }
    }

    public static void Demo(int ms)
    {
        Application.EnableVisualStyles();
        Show();
        System.Windows.Forms.Timer t = new System.Windows.Forms.Timer();
        t.Interval = ms;
        t.Tick += delegate { t.Stop(); t.Dispose(); Shutdown(); };
        t.Start();
        Application.Run();
    }

    public static void Show()
    {
        if (IsShown) return;
        // 灭屏模式安全检查：必须有密码才能灭屏（否则无法解锁）
        if (ScreenOff && string.IsNullOrEmpty(Password))
        {
            ScreenOff = false;
            Log("灭屏已自动关闭：未设密码，灭屏后无法解锁。");
        }
        List<OverlayForm> created = new List<OverlayForm>();
        foreach (Screen s in Screen.AllScreens)
        {
            OverlayForm f = new OverlayForm(s.Bounds, Mode, ImagePath, EatClicks, CustomText, AntiBurn);
            f.Show();
            created.Add(f);
        }
        _overlays = created;
        if (ScreenOff)
        {
            Native.SendMessage((IntPtr)0xFFFF, Native.WM_SYSCOMMAND, (IntPtr)Native.SC_MONITORPOWER, (IntPtr)2);
        }
        if (DimBrightness) DimToZero(true);

        bool needBlocker = BlockMouse || !string.IsNullOrEmpty(Password);
        if (needBlocker && _inputBlocker == null)
        {
            try
            {
                _inputBlocker = new InputBlocker(Password, BlockMouse, UnlockByPassword, ToggleRemoteMode);
                _inputBlocker.PassThrough = _remoteActive;
                if (!_inputBlocker.KeyboardInstalled)
                {
                    Log("键盘监听安装失败：密码解锁不可用，紧急退出请用 Ctrl+Alt+Del -> 任务管理器。");
                }
                if (BlockMouse)
                {
                    if (_inputBlocker.MouseInstalled) Log("鼠标屏蔽已生效（真人鼠标指针/点击被吞，AI 注入输入放行）。");
                    else Log("鼠标屏蔽未生效（鼠标钩子安装失败）。");
                }
            }
            catch (Exception ex)
            {
                Log("输入屏蔽初始化异常：" + ex.Message);
            }
        }

        if (BlockTouchpad)
        {
            if (Touchpad.UseDeviceMode && Touchpad.DeviceModeConfigured())
            {
                if (Touchpad.DeviceDisable()) Log("已禁用触控板设备并确认生效（指针 + 三指/四指手势全部失效），解锁后自动启用。");
                else
                {
                    string st;
                    Touchpad.DeviceUsable(out st);
                    Log("触控板设备禁用未确认生效（" + st + "），回退到注册表开关。");
                    if (Touchpad.Disable()) Log("已回退：注册表开关已关闭触控板。");
                }
            }
            else if (Touchpad.Available)
            {
                if (Touchpad.Disable()) Log("触控板总开关已关闭 + 三指/四指手势开关置 0（注意：实测对三指手势可能无效），解锁后自动恢复。");
                else Log("触控板关闭失败（注册表写入被拒绝），手势可能仍可用。");
            }
            else
            {
                Log("未找到精密触控板设置项（PrecisionTouchPad\\Status），无法通过注册表屏蔽手势。");
            }
        }
        Log("遮罩已显示（模式=" + Mode + "，防烧屏=" + (AntiBurn ? "开" : "关") + "）。");
    }

    public static void Hide()
    {
        if (_inputBlocker != null)
        {
            try { _inputBlocker.Dispose(); } catch { }
            _inputBlocker = null;
        }
        if (BlockTouchpad)
        {
            if (Touchpad.UseDeviceMode && Touchpad.DeviceModeConfigured())
            {
                if (Touchpad.DeviceEnable()) Log("触控板设备已恢复可用。");
                else Log("触控板设备恢复未确认成功，请运行 恢复触控板.cmd。");
            }
            else
            {
                Touchpad.Restore();
            }
        }
        foreach (OverlayForm f in _overlays)
        {
            try { f.Dispose(); } catch { }
        }
        _overlays.Clear();
        if (DimBrightness) DimToZero(false);
        if (ScreenOff)
        {
            Native.SendMessage((IntPtr)0xFFFF, Native.WM_SYSCOMMAND, (IntPtr)Native.SC_MONITORPOWER, (IntPtr)1);
        }
        Log("遮罩已隐藏，输入与触控板已恢复。");
    }

    private static void UnlockByPassword()
    {
        Hide();
    }

    public static void Toggle()
    {
        if (IsShown)
        {
            if (!string.IsNullOrEmpty(Password)) return; // 需输入密码解锁，热键不收起
            Hide();
        }
        else
        {
            Show();
        }
    }

    private static ContextMenuStrip _menu;

    private static void SetupTray()
    {
        _tray = new NotifyIcon();
        _tray.Icon = MakeIcon();
        _tray.Text = "隐私屏 - " + Mode;
        _tray.Visible = true;
        _menu = BuildMenu();
        _tray.ContextMenuStrip = _menu;
        _tray.DoubleClick += delegate { Toggle(); };
    }

    private static ContextMenuStrip BuildMenu()
    {
        ContextMenuStrip menu = new ContextMenuStrip();

        // 遮罩操作
        ToolStripMenuItem show = new ToolStripMenuItem("显示遮罩");
        show.Click += delegate { Show(); };
        ToolStripMenuItem hide = new ToolStripMenuItem("隐藏遮罩");
        hide.Enabled = string.IsNullOrEmpty(Password);
        hide.Click += delegate { Toggle(); };

        // 模式切换
        ToolStripMenuItem modeMenu = new ToolStripMenuItem("遮罩模式");
        string[] modeNames = { "maintenance", "black", "lockstyle" };
        string[] modeLabels = { "维护伪装", "纯黑屏", "锁屏伪装" };
        for (int i = 0; i < modeNames.Length; i++)
        {
            string m = modeNames[i];
            string label = modeLabels[i];
            ToolStripMenuItem mi = new ToolStripMenuItem(label);
            mi.Checked = (Mode == m);
            mi.Click += delegate
            {
                if (Mode != m)
                {
                    Mode = m;
                    Log("遮罩模式已切换为 " + label + "。");
                    if (IsShown) { Hide(); Show(); }
                    _tray.Text = "隐私屏 - " + Mode;
                    SaveSettings();
                    RebuildMenu();
                }
            };
            modeMenu.DropDownItems.Add(mi);
        }
        // 功能开关子菜单
        ToolStripMenuItem opts = new ToolStripMenuItem("功能开关");

        opts.DropDownItems.Add(MakeToggle("防烧屏", AntiBurn, delegate(bool v) {
            ToggleBool("防烧屏", v,
                val => (val && ScreenOff) ? "无法开启防烧屏：灭屏模式下防烧屏无意义，请先关闭灭屏。" : null,
                val => AntiBurn = val,
                true);
        }));

        opts.DropDownItems.Add(MakeToggle("屏蔽鼠标", BlockMouse, delegate(bool v) {
            ToggleBool("鼠标屏蔽", v,
                val => (val && string.IsNullOrEmpty(Password)) ? "无法开启屏蔽鼠标：未设密码，屏蔽后无法解锁。请先设密码。" : null,
                val => BlockMouse = val,
                true);
        }));

        opts.DropDownItems.Add(MakeToggle("屏蔽触控板", BlockTouchpad, delegate(bool v) {
            ToggleBool("触控板屏蔽", v, null, val => BlockTouchpad = val, true);
        }));

        opts.DropDownItems.Add(MakeToggle("吞掉点击", EatClicks, delegate(bool v) {
            ToggleBool("吞掉点击", v, null, val => EatClicks = val, true);
        }));

        opts.DropDownItems.Add(MakeToggle("灭屏", ScreenOff, delegate(bool v) {
            if (v)
            {
                if (string.IsNullOrEmpty(Password))
                {
                    Log("无法开启灭屏：未设密码，灭屏后无法解锁。请先设密码。");
                    return;
                }
                // 灭屏时自动关闭防烧屏和压亮度（屏幕都关了，漂移和压亮度无意义）
                if (AntiBurn) { _antiBurnBeforeScreenOff = true; AntiBurn = false; }
                else _antiBurnBeforeScreenOff = false;
                if (DimBrightness) { _dimBrightnessBeforeScreenOff = true; DimBrightness = false; }
                else _dimBrightnessBeforeScreenOff = false;
            }
            else
            {
                // 关闭灭屏时恢复之前的状态
                if (_antiBurnBeforeScreenOff == true) { AntiBurn = true; Log("防烧屏已自动恢复（灭屏关闭）。"); }
                _antiBurnBeforeScreenOff = null;
                if (_dimBrightnessBeforeScreenOff == true) { DimBrightness = true; Log("压亮度已自动恢复（灭屏关闭）。"); }
                _dimBrightnessBeforeScreenOff = null;
            }
            ScreenOff = v;
            if (IsShown) { Hide(); Show(); }
            RebuildMenu();
            Log("物理灭屏已" + (v ? "开启" : "关闭") + "。");
        }));

        opts.DropDownItems.Add(MakeToggle("压亮度", DimBrightness, delegate(bool v) {
            ToggleBool("压亮度", v,
                val => (val && ScreenOff) ? "无法开启压亮度：灭屏模式下压亮度无意义，请先关闭灭屏。" : null,
                val => DimBrightness = val,
                true);
        }));

        opts.DropDownItems.Add(MakeToggle("远程检测", RemoteDetect, delegate(bool v) {
            RemoteDetect = v;
            if (v && _remoteTimer == null) StartRemoteWatch();
            else if (!v && _remoteTimer != null) { _remoteTimer.Stop(); _remoteTimer.Dispose(); _remoteTimer = null; }
            // 关闭远程检测时，远控收遮罩也一并关闭（无依赖）
            if (!v && RemoteHideOverlay)
            {
                RemoteHideOverlay = false;
                Log("远控收遮罩已联动关闭（远程检测已关闭）。");
            }
            RebuildMenu();
            Log("远程检测已" + (v ? "开启" : "关闭") + "。");
        }));

        opts.DropDownItems.Add(MakeToggle("远控收遮罩", RemoteHideOverlay, delegate(bool v) {
            if (v && !RemoteDetect)
            {
                Log("无法开启远控收遮罩：远程检测已关闭。请先开启远程检测。");
                return;
            }
            RemoteHideOverlay = v;
            Log("远控收遮罩已" + (v ? "开启" : "关闭") + "。");
        }));

        // 密码管理
        ToolStripMenuItem pwdMenu = new ToolStripMenuItem("密码管理");
        ToolStripMenuItem changePwd = new ToolStripMenuItem("修改密码...");
        changePwd.Click += delegate { ChangePasswordDialog(); };
        ToolStripMenuItem clearPwd = new ToolStripMenuItem("关闭密码");
        clearPwd.Enabled = !string.IsNullOrEmpty(Password);
        clearPwd.Click += delegate { ClearPassword(); };
        pwdMenu.DropDownItems.Add(changePwd);
        pwdMenu.DropDownItems.Add(clearPwd);

        // 热键设置
        ToolStripMenuItem hotkeyMenu = new ToolStripMenuItem("热键设置");
        ToolStripMenuItem changeHotkey = new ToolStripMenuItem("修改切换热键...");
        changeHotkey.Click += delegate { ChangeHotkeyDialog(); };
        ToolStripMenuItem hotkeyInfo = new ToolStripMenuItem("当前: " + Hotkey);
        hotkeyInfo.Enabled = false;
        hotkeyMenu.DropDownItems.Add(changeHotkey);
        hotkeyMenu.DropDownItems.Add(hotkeyInfo);

        // 退出
        ToolStripMenuItem exit = new ToolStripMenuItem("退出");
        exit.Click += delegate { Shutdown(); };

        menu.Items.Add(show);
        menu.Items.Add(hide);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(modeMenu);
        menu.Items.Add(opts);
        menu.Items.Add(pwdMenu);
        menu.Items.Add(hotkeyMenu);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(exit);

        return menu;
    }

    private static ToolStripMenuItem MakeToggle(string label, bool current, Action<bool> onToggle)
    {
        ToolStripMenuItem item = new ToolStripMenuItem(label);
        item.Checked = current;
        item.CheckOnClick = true;
        item.Click += delegate
        {
            onToggle(item.Checked);
            SaveSettings();
        };
        return item;
    }

    // 通用布尔开关切换：验证→赋值→刷新遮罩→打日志
    // 返回 true 表示切换成功，false 表示被验证规则拦截
    private static bool ToggleBool(string name, bool newValue,
        Func<bool, string> validator, Action<bool> applier, bool needRefresh)
    {
        string err = validator != null ? validator(newValue) : null;
        if (err != null) { Log(err); return false; }
        applier(newValue);
        if (needRefresh && IsShown) { Hide(); Show(); }
        Log(name + "已" + (newValue ? "开启" : "关闭") + "。");
        return true;
    }

    private static void RebuildMenu()
    {
        if (_menu != null)
        {
            _tray.ContextMenuStrip = BuildMenu();
        }
    }

    // ---------- 配置持久化 ----------

    private static string SettingsPath { get { return Path.Combine(AppDir, "settings.conf"); } }
    private static string SettingsPathLegacy { get { return Path.Combine(AppDir, "配置.txt"); } }

    // 配置项描述符：key / 读取 / 写入 / 切换时是否需要刷新遮罩
    private struct SettingDesc
    {
        public string Key;
        public Func<bool> Get;
        public Action<bool> Set;
        public bool NeedRefresh;
        public SettingDesc(string k, Func<bool> g, Action<bool> s, bool r) { Key = k; Get = g; Set = s; NeedRefresh = r; }
    }

    private static SettingDesc[] BoolSettings = new SettingDesc[] {
        new SettingDesc("AntiBurn",          () => AntiBurn,          v => AntiBurn = v,          true),
        new SettingDesc("BlockMouse",        () => BlockMouse,        v => BlockMouse = v,        true),
        new SettingDesc("BlockTouchpad",     () => BlockTouchpad,     v => BlockTouchpad = v,     true),
        new SettingDesc("EatClicks",         () => EatClicks,         v => EatClicks = v,         true),
        new SettingDesc("ScreenOff",         () => ScreenOff,         v => ScreenOff = v,         true),
        new SettingDesc("DimBrightness",     () => DimBrightness,     v => DimBrightness = v,     true),
        new SettingDesc("RemoteDetect",      () => RemoteDetect,      v => RemoteDetect = v,      false),
        new SettingDesc("RemoteHideOverlay", () => RemoteHideOverlay, v => RemoteHideOverlay = v, false),
    };

    public static void SaveSettings()
    {
        try
        {
            StringBuilder sb = new StringBuilder();
            sb.AppendLine("Mode=" + Mode);
            sb.AppendLine("Hotkey=" + Hotkey);
            foreach (SettingDesc s in BoolSettings)
                sb.AppendLine(s.Key + "=" + (s.Get() ? "1" : "0"));
            File.WriteAllText(SettingsPath, sb.ToString(), Encoding.UTF8);
        }
        catch { }
    }

    public static void LoadSettings()
    {
        try
        {
            string path = File.Exists(SettingsPath) ? SettingsPath :
                          File.Exists(SettingsPathLegacy) ? SettingsPathLegacy : null;
            if (path == null) return;
            string[] lines = File.ReadAllLines(path, Encoding.UTF8);
            Dictionary<string, string> kv = new Dictionary<string, string>();
            foreach (string line in lines)
            {
                int idx = line.IndexOf('=');
                if (idx > 0) kv[line.Substring(0, idx).Trim()] = line.Substring(idx + 1).Trim();
            }
            string g;
            if (kv.TryGetValue("Mode", out g) &&
                (g == "maintenance" || g == "black" || g == "lockstyle")) Mode = g;
            if (kv.TryGetValue("Hotkey", out g) && !string.IsNullOrEmpty(g)) Hotkey = g;
            foreach (SettingDesc s in BoolSettings)
                if (kv.TryGetValue(s.Key, out g)) s.Set(g == "1");
        }
        catch { }
    }

    private static Icon MakeIcon()
    {
        Bitmap bmp = new Bitmap(32, 32);
        using (Graphics g = Graphics.FromImage(bmp))
        {
            g.Clear(Color.Transparent);
            g.FillEllipse(Brushes.SteelBlue, 2, 2, 28, 28);
            g.FillEllipse(Brushes.WhiteSmoke, 10, 10, 12, 12);
        }
        return Icon.FromHandle(bmp.GetHicon());
    }

    private static void SetupHotkey(string spec)
    {
        uint mods, vk;
        if (!HotkeyParser.TryParse(spec, out mods, out vk))
        {
            Log("热键格式无法识别: " + spec + "，本次仅可用托盘图标操作。");
            return;
        }
        try { if (_hotkeyHost != null) { Native.UnregisterHotKey(_hotkeyHost.Handle, 1); _hotkeyHost.ReleaseHandle(); _hotkeyHost = null; } } catch { }
        _hotkeyHost = new HotkeyHost(Toggle);
        if (Native.RegisterHotKey(_hotkeyHost.Handle, 1, mods, vk))
        {
            Hotkey = spec;
            Log("热键已注册: " + spec);
        }
        else
        {
            Log("热键注册失败（可能已被其他程序占用），请使用托盘图标操作。");
            try { if (_hotkeyHost != null) { _hotkeyHost.ReleaseHandle(); _hotkeyHost = null; } } catch { }
        }
    }

    public static void ChangeHotkeyDialog()
    {
        Form dlg = CreateDialog("修改热键", 360, 180);

        Label lbl = new Label();
        lbl.Text = "新热键（格式：Ctrl+Shift+Alt+F12）：";
        lbl.Location = new Point(20, 20);
        lbl.Size = new Size(310, 20);

        TextBox txt = new TextBox();
        txt.Text = Hotkey;
        txt.Location = new Point(20, 50);
        txt.Size = new Size(310, 20);

        Button ok = new Button();
        ok.Text = "确定";
        ok.Location = new Point(170, 85);
        ok.Size = new Size(75, 25);
        ok.DialogResult = DialogResult.OK;

        Button cancel = new Button();
        cancel.Text = "取消";
        cancel.Location = new Point(255, 85);
        cancel.Size = new Size(75, 25);
        cancel.DialogResult = DialogResult.Cancel;

        dlg.Controls.Add(lbl);
        dlg.Controls.Add(txt);
        dlg.Controls.Add(ok);
        dlg.Controls.Add(cancel);
        dlg.AcceptButton = ok;
        dlg.CancelButton = cancel;

        if (dlg.ShowDialog() == DialogResult.OK)
        {
            string newKey = txt.Text.Trim();
            uint m, v;
            if (!HotkeyParser.TryParse(newKey, out m, out v))
            {
                MessageBox.Show("热键格式不正确。示例：Ctrl+Alt+F12、Shift+F9、Win+P", "错误",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            else
            {
                SetupHotkey(newKey);
                SaveSettings();
                RebuildMenu();
            }
        }
        dlg.Dispose();
    }

    private static void Shutdown()
    {
        Hide();
        try { if (_hotkeyHost != null) _hotkeyHost.ReleaseHandle(); } catch { }
        try { if (_tray != null) { _tray.Visible = false; _tray.Dispose(); } } catch { }
        try { if (_mutex != null) _mutex.ReleaseMutex(); } catch { }
        Application.ExitThread();
    }

    private static void DimToZero(bool dim)
    {
        if (!dim)
        {
            foreach (object[] item in _brightness)
            {
                try
                {
                    IntPtr h = (IntPtr)item[0];
                    uint cur = (uint)item[1];
                    uint min = (uint)item[2];
                    uint max = (uint)item[3];
                    if (cur <= min + (max - min) * 10 / 100) cur = min + (max - min) * 45 / 100;
                    Native.SetMonitorBrightness(h, cur);
                }
                catch { }
            }
            _brightness.Clear();
            return;
        }

        Native.EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero,
            delegate(IntPtr hMonitor, IntPtr hdc, ref Native.NativeRect rect, IntPtr data)
            {
                try
                {
                    uint count = 0;
                    Native.GetNumberOfPhysicalMonitorsFromHMONITOR(hMonitor, ref count);
                    if (count == 0) count = 1;
                    Native.PhysicalMonitor[] arr = new Native.PhysicalMonitor[count];
                    if (Native.GetPhysicalMonitorsFromHMONITOR(hMonitor, count, arr))
                    {
                        foreach (Native.PhysicalMonitor pm in arr)
                        {
                            uint mn = 0, cur = 0, mx = 0;
                            if (Native.GetMonitorBrightness(pm.hPhysicalMonitor, ref mn, ref cur, ref mx))
                            {
                                _brightness.Add(new object[] { pm.hPhysicalMonitor, cur, mn, mx });
                                Native.SetMonitorBrightness(pm.hPhysicalMonitor, mn);
                            }
                        }
                    }
                }
                catch { }
                return true;
            }, IntPtr.Zero);
    }

    public static string SelfTest()
    {
        StringBuilder sb = new StringBuilder();
        Screen screen = Screen.PrimaryScreen;
        int w = 320, h = 200;
        Rectangle r = new Rectangle(screen.WorkingArea.Right - w - 30, screen.WorkingArea.Bottom - h - 30, w, h);
        Color test = Color.FromArgb(233, 30, 99);
        OverlayForm f = new OverlayForm(r, "black", null, false, "", false);
        f.BackColor = test;
        f.Show();
        Application.DoEvents();
        Thread.Sleep(2000);
        Application.DoEvents();

        int hits = 0, total = 0;
        int rSum = 0, gSum = 0, bSum = 0;
        using (Bitmap bmp = new Bitmap(w, h))
        {
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.CopyFromScreen(r.X, r.Y, 0, 0, new Size(w, h));
            }
            for (int y = 0; y < h; y += 16)
            {
                for (int x = 0; x < w; x += 16)
                {
                    Color c = bmp.GetPixel(x, y);
                    total++;
                    rSum += c.R; gSum += c.G; bSum += c.B;
                    if (Math.Abs(c.R - test.R) < 40 && Math.Abs(c.G - test.G) < 40 && Math.Abs(c.B - test.B) < 40) hits++;
                }
            }
        }
        f.Dispose();

        sb.AppendLine("----------------------------------------");
        sb.AppendLine("自检结果（GDI 截图路径）");
        sb.AppendLine("  1) 物理屏幕：如果刚才在屏幕右下角看到了粉色色块，说明遮罩能正常显示。");
        sb.AppendLine("  2) 截图豁免：用 GDI 截图抓取同一区域，色块命中 " + hits + "/" + total + " 个采样点，");
        sb.AppendLine("     截图平均色 RGB(" + (rSum / total) + "," + (gSum / total) + "," + (bSum / total) + ")。");
        if (hits * 2 > total)
        {
            sb.AppendLine("  => 失败：GDI 截图里能看到遮罩（截图豁免未生效）。");
            sb.AppendLine("     建议：改用 selfcheck.ps1 做完整双路径诊断；或改用 -ScreenOff 模式。");
        }
        else
        {
            sb.AppendLine("  => 成功：GDI 截图看到的是遮罩背后的真实桌面，截图豁免生效。");
        }
        sb.AppendLine("  提示：DXGI（OBS 类）与 WGC 路径请运行 selfcheck.ps1 做完整实测。");
        sb.AppendLine("----------------------------------------");
        return sb.ToString();
    }

    // ---------- 密码修改对话框 ----------

    private static Form CreateDialog(string title, int width, int height)
    {
        Form dlg = new Form();
        dlg.Text = title;
        dlg.FormBorderStyle = FormBorderStyle.FixedDialog;
        dlg.StartPosition = FormStartPosition.CenterScreen;
        dlg.TopMost = true;
        dlg.Width = width;
        dlg.Height = height;
        dlg.MaximizeBox = false;
        dlg.MinimizeBox = false;
        return dlg;
    }

    public static void ChangePasswordDialog()
    {
        bool wasPassThrough = (_inputBlocker != null && _inputBlocker.PassThrough);
        if (_inputBlocker != null) _inputBlocker.PassThrough = true;

        try
        {
            Form dlg = CreateDialog("修改密码", 360, 200);

            Label lbl = new Label();
            lbl.Text = "新密码（仅数字和字母，区分大小写）：";
            lbl.Location = new Point(20, 20);
            lbl.Size = new Size(300, 20);

            TextBox txt = new TextBox();
            txt.Location = new Point(20, 50);
            txt.Size = new Size(310, 20);
            txt.UseSystemPasswordChar = true;

            Button ok = new Button();
            ok.Text = "确定";
            ok.Location = new Point(170, 90);
            ok.Size = new Size(75, 25);
            ok.DialogResult = DialogResult.OK;

            Button cancel = new Button();
            cancel.Text = "取消";
            cancel.Location = new Point(255, 90);
            cancel.Size = new Size(75, 25);
            cancel.DialogResult = DialogResult.Cancel;

            dlg.Controls.Add(lbl);
            dlg.Controls.Add(txt);
            dlg.Controls.Add(ok);
            dlg.Controls.Add(cancel);
            dlg.AcceptButton = ok;
            dlg.CancelButton = cancel;

            if (dlg.ShowDialog() == DialogResult.OK && txt.Text.Length > 0)
            {
                string newPwd = txt.Text;
                Password = newPwd;
                if (_inputBlocker != null) _inputBlocker.UpdatePassword(newPwd);
                try { File.WriteAllText(Path.Combine(AppDir, "password.txt"), newPwd, Encoding.UTF8); } catch { }
                Log("密码已修改并保存（长度 " + newPwd.Length + "）。");
                RebuildMenu();
            }
            dlg.Dispose();
        }
        catch (Exception ex)
        {
            Log("修改密码异常：" + ex.Message);
        }
        finally
        {
            if (_inputBlocker != null) _inputBlocker.PassThrough = wasPassThrough;
        }
    }

    public static void ClearPassword()
    {
        bool wasPassThrough = (_inputBlocker != null && _inputBlocker.PassThrough);
        if (_inputBlocker != null) _inputBlocker.PassThrough = true;

        try
        {
            Form dlg = CreateDialog("关闭密码", 360, 170);

            Label lbl = new Label();
            lbl.Text = "关闭后遮罩期间无密码解锁，热键可直接收起。确定？";
            lbl.Location = new Point(20, 20);
            lbl.Size = new Size(310, 40);

            Button ok = new Button();
            ok.Text = "确定关闭";
            ok.Location = new Point(145, 70);
            ok.Size = new Size(90, 25);
            ok.DialogResult = DialogResult.OK;

            Button cancel = new Button();
            cancel.Text = "取消";
            cancel.Location = new Point(245, 70);
            cancel.Size = new Size(75, 25);
            cancel.DialogResult = DialogResult.Cancel;

            dlg.Controls.Add(lbl);
            dlg.Controls.Add(ok);
            dlg.Controls.Add(cancel);
            dlg.AcceptButton = ok;
            dlg.CancelButton = cancel;

            if (dlg.ShowDialog() == DialogResult.OK)
            {
                Password = "";
                if (_inputBlocker != null) _inputBlocker.UpdatePassword("");
                try { File.Delete(Path.Combine(AppDir, "password.txt")); } catch { }
                // 无密码时，依赖密码的功能全部关闭
                if (BlockMouse)
                {
                    BlockMouse = false;
                    Log("鼠标屏蔽已联动关闭（无密码时屏蔽鼠标会导致无法解锁）。");
                }
                if (ScreenOff)
                {
                    ScreenOff = false;
                    Log("灭屏已联动关闭（无密码时灭屏会导致无法解锁）。");
                }
                if (IsShown) { Hide(); Show(); }
                Log("密码已关闭。");
                SaveSettings();
                RebuildMenu();
            }
            dlg.Dispose();
        }
        catch (Exception ex)
        {
            Log("关闭密码异常：" + ex.Message);
        }
        finally
        {
            if (_inputBlocker != null) _inputBlocker.PassThrough = wasPassThrough;
        }
    }
}
'@

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition $src -ReferencedAssemblies 'System.Windows.Forms', 'System.Drawing'

[Native]::SetProcessDPIAware() | Out-Null

if ($CompileOnly) {
    Write-Host 'OK: 代码编译通过。'
    exit 0
}

function Read-MaskTextFile {
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    $strict = New-Object System.Text.UTF8Encoding($false, $true)
    try {
        return $strict.GetString($bytes)
    }
    catch {
        try { return ([Text.Encoding]::GetEncoding(936)).GetString($bytes) }
        catch { return [Text.Encoding]::Default.GetString($bytes) }
    }
}

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

# 查找配置文件：优先英文名，兼容旧中文名
function Find-ConfigFile {
    param([string]$EngName, [string]$CnName)
    $eng = Join-Path $scriptDir $EngName
    $cn = Join-Path $scriptDir $CnName
    if (Test-Path -LiteralPath $eng) { return $eng }
    if (Test-Path -LiteralPath $cn) { return $cn }
    return $eng  # 默认用英文名（可能不存在，由调用方处理）
}

$textFile = Find-ConfigFile 'overlay-text.txt' '遮罩文字.txt'
$textFromFile = $false
if (-not $Text -and (Test-Path -LiteralPath $textFile)) {
    $fileText = Read-MaskTextFile -Path $textFile
    if (-not [string]::IsNullOrWhiteSpace($fileText)) {
        $Text = $fileText.Trim()
        $textFromFile = $true
    }
}

# 密码文件优先于命令行 -Password 参数
$pwdFile = Find-ConfigFile 'password.txt' '密码.txt'
if (Test-Path -LiteralPath $pwdFile) {
    $filePwd = Read-MaskTextFile -Path $pwdFile
    if ($filePwd -ne $null -and $filePwd.Trim() -ne '') {
        $Password = $filePwd.Trim()
    } elseif ($filePwd -ne $null -and $filePwd.Trim() -eq '') {
        $Password = ''
    }
}

[PrivacyEngine]::AppDir = $scriptDir

# 先从配置文件加载上次保存的开关状态
[PrivacyEngine]::LoadSettings()

# 命令行明确传递的参数覆盖配置文件的值
if ($PSBoundParameters.ContainsKey('Mode')) { [PrivacyEngine]::Mode = $Mode }
if ($PSBoundParameters.ContainsKey('Hotkey')) { [PrivacyEngine]::Hotkey = $Hotkey }
[PrivacyEngine]::ImagePath = $ImagePath
[PrivacyEngine]::CustomText = $Text
[PrivacyEngine]::Password = $Password
if ($PSBoundParameters.ContainsKey('ScreenOff')) { [PrivacyEngine]::ScreenOff = $ScreenOff.IsPresent }
if ($PSBoundParameters.ContainsKey('DimBrightness')) { [PrivacyEngine]::DimBrightness = $DimBrightness.IsPresent }
if ($PSBoundParameters.ContainsKey('EatClicks')) { [PrivacyEngine]::EatClicks = $EatClicks.IsPresent }
if ($PSBoundParameters.ContainsKey('BlockMouse')) { [PrivacyEngine]::BlockMouse = $BlockMouse }
if ($PSBoundParameters.ContainsKey('BlockTouchpad')) { [PrivacyEngine]::BlockTouchpad = $BlockTouchpad }
if ($PSBoundParameters.ContainsKey('AntiBurn')) { [PrivacyEngine]::AntiBurn = $AntiBurn }
if ($PSBoundParameters.ContainsKey('RemoteDetect')) { [PrivacyEngine]::RemoteDetect = $RemoteDetect }
if ($PSBoundParameters.ContainsKey('RemoteHideOverlay')) { [PrivacyEngine]::RemoteHideOverlay = $RemoteHideOverlay }

# 无密码时强制关闭鼠标屏蔽（否则无法解锁）
if ([PrivacyEngine]::BlockMouse -and -not [PrivacyEngine]::Password) {
    Write-Warning '[隐私屏] 未设置密码，鼠标屏蔽已自动关闭（否则没有任何解锁方式）。'
    [PrivacyEngine]::BlockMouse = $false
}
[PrivacyEngine]::RemoteEndPolls = [int][Math]::Max(1, [Math]::Ceiling($RemoteEndDelaySec / 1.5))
[PrivacyEngine]::RemoteProcesses = $RemoteProcesses
$logFile = Find-ConfigFile 'privacy-screen.log' '隐私屏日志.txt'
[PrivacyEngine]::LogPath = $logFile

$touchpadIdFile = Find-ConfigFile 'touchpad-device.txt' '触控板设备.txt'
[Touchpad]::DeviceIdFile = $touchpadIdFile
if (Test-Path -LiteralPath $touchpadIdFile) {
    try { [Touchpad]::DeviceId = (Get-Content -LiteralPath $touchpadIdFile -Raw).Trim() } catch { }
}
if ($TouchpadMode -eq 'off') { [PrivacyEngine]::BlockTouchpad = $false }
elseif ($TouchpadMode -eq 'device') { [Touchpad]::UseDeviceMode = $true }
elseif ($TouchpadMode -eq 'auto') { [Touchpad]::UseDeviceMode = (Test-Path -LiteralPath $touchpadIdFile) }

if ($SetupTouchpadDevice -or $RemoveTouchpadDevice) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host '[隐私屏] 需要管理员权限操作"禁用/启用触控板"的计划任务，正在申请提权（会弹 UAC）...'
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
        if ($SetupTouchpadDevice) { $argList += '-SetupTouchpadDevice' } else { $argList += '-RemoveTouchpadDevice' }
        if ($TouchpadInstanceId) { $argList += @('-TouchpadInstanceId', $TouchpadInstanceId) }
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList
        exit 0
    }

    if ($RemoveTouchpadDevice) {
        & schtasks /delete /tn 'PrivacyScreen-TouchpadOff' /f 2>$null | Out-Null
        & schtasks /delete /tn 'PrivacyScreen-TouchpadOn' /f 2>$null | Out-Null
        Remove-Item -LiteralPath $touchpadIdFile -ErrorAction SilentlyContinue
        Write-Host '[隐私屏] 已删除触控板计划任务并清除设备记录。'
        exit 0
    }

    $id = $TouchpadInstanceId
    if (-not $id) {
        $cands = @(Get-PnpDevice -Class Mouse, HIDClass -ErrorAction SilentlyContinue |
            Where-Object { $_.FriendlyName -match '触控板|触摸板|touch ?pad|I2C HID|精密' })
        if ($cands.Count -eq 0) {
            Write-Warning '[隐私屏] 没找到触控板设备。请用 -TouchpadInstanceId "设备实例ID" 手动指定（设备管理器 -> 触控板 -> 属性 -> 详细信息 -> 设备实例路径）。'
            exit 1
        }
        Write-Host '候选触控板设备：'
        $i = 0
        foreach ($c in $cands) { Write-Host ("  [{0}] {1}  {2}  ({3})" -f $i, $c.FriendlyName, $c.InstanceId, $c.Status); $i++ }
        $id = $cands[0].InstanceId
        Write-Host "选用第 0 项：$id"
    }

    Set-Content -LiteralPath $touchpadIdFile -Value $id -Encoding UTF8
    $trOff = 'pnputil /disable-device "' + $id + '"'
    $trOn = 'pnputil /enable-device "' + $id + '"'
    & schtasks /create /tn 'PrivacyScreen-TouchpadOff' /tr $trOff /sc once /st 00:00 /rl highest /f | Out-Null
    & schtasks /create /tn 'PrivacyScreen-TouchpadOn' /tr $trOn /sc once /st 00:00 /rl highest /f | Out-Null
    Write-Host ''
    Write-Host '[隐私屏] 完成：已建立两个计划任务（禁用/启用触控板设备），设备记录写入 触控板设备.txt。'
    Write-Host '         之后启动隐私屏会自动以设备级方式禁用触控板，无需再提权。'
    Write-Host '         想撤销：privacy-screen.ps1 -RemoveTouchpadDevice'
    exit 0
}

if ($ScanRemote) {
    [RemoteSession]::ProcessList = $RemoteProcesses
    Write-Host ''
    Write-Host ([RemoteSession]::Scan())
    exit 0
}

if ($FixTouchpad) {
    [Touchpad]::Restore()
    if ([Touchpad]::UseDeviceMode -and [Touchpad]::DeviceModeConfigured()) {
        Write-Host '[隐私屏] 正在通过计划任务启用触控板设备...'
        if ([Touchpad]::DeviceEnable()) { Write-Host '[隐私屏] 触控板设备已恢复可用。' }
        else { Write-Warning '[隐私屏] 启用任务执行后设备仍不可用，请到 设置 -> 蓝牙和其他设备 -> 触控板 手动打开，或设备管理器里启用。' }
    }
    else {
        Write-Host '[隐私屏] 已把注册表开关恢复为开启（若仍无效，请到 设置 -> 蓝牙和其他设备 -> 触控板 里手动打开）。'
    }
    $st = ''
    if ([Touchpad]::DeviceUsable([ref]$st)) { Write-Host "[隐私屏] 设备状态：可用（$st）" } else { Write-Host "[隐私屏] 设备状态：不可用（$st）" }
    exit 0
}

if ($SelfTest) {
    Write-Host ''
    Write-Host '正在自检：屏幕右下角会出现一个约 2 秒的粉色测试色块（请确认你能看到它）。'
    Write-Host ''
    Write-Host ([PrivacyEngine]::SelfTest())
    exit 0
}

if ($DemoMs -gt 0) {
    Write-Host ''
    Write-Host "[隐私屏] 演示模式：遮罩显示 $($DemoMs / 1000) 秒后自动隐藏并退出。"
    [PrivacyEngine]::Demo($DemoMs)
    exit 0
}

if ($Replace) {
    try {
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop |
            Where-Object { $_.CommandLine -and $_.CommandLine -like '*privacy-screen.ps1*' -and $_.ProcessId -ne $PID } |
            ForEach-Object {
                Write-Host "[隐私屏] 结束旧实例 PID=$($_.ProcessId)"
                Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            }
        Start-Sleep -Milliseconds 1000
    }
    catch {
        Write-Warning "[隐私屏] 未能自动结束旧实例（无法查询进程列表）：$($_.Exception.Message)"
        Write-Warning '           可手动：Ctrl+Alt+Del -> 任务管理器 -> 结束 Windows PowerShell。'
    }
}

if (-not [PrivacyEngine]::TryAcquireSingleInstance()) {
    Write-Host '[隐私屏] 已有实例在运行（可能是旧版本）。'
    Write-Host '         想用当前版本替换它：加 -Replace 参数，或先退出托盘里的旧实例。'
    exit 1
}

if ($Mode -eq 'image' -and -not $ImagePath) {
    Write-Warning '[隐私屏] 模式为 image 但未提供 -ImagePath，将显示纯色遮罩。'
}

$build = [Environment]::OSVersion.Version.Build
if ($build -lt 19041) {
    Write-Warning "[隐私屏] 当前系统版本 ($build) 低于 Windows 10 2004 (19041)：截图豁免可能不生效，遮罩可能出现在软件截图里。"
}

Write-Host ''
Write-Host '[隐私屏] 已启动'
Write-Host "  模式       : $Mode"
Write-Host "  热键       : $([PrivacyEngine]::Hotkey) (显示/隐藏遮罩)"
if ($Password) { Write-Host "  密码       : 已设置（遮罩显示时直接键入即可解锁，无任何提示）" }
if ($Text) {
    if ($textFromFile) { Write-Host '  自定义文字 : 已从 遮罩文字.txt 读取' }
    else { Write-Host '  自定义文字 : 已设置（命令行 -Text）' }
}
if ($ScreenOff) { Write-Host '  屏幕断电   : 开启（遮罩显示时同时关闭显示器电源）' }
if ($DimBrightness) { Write-Host '  亮度归零   : 开启（隐藏时自动恢复）' }
if ($EatClicks) { Write-Host '  拦截鼠标   : 开启（注意：AI 的鼠标操作也会被挡）' }
if ($BlockMouse) { Write-Host '  屏蔽鼠标   : 开启（真人鼠标/触控板指针在遮罩期间完全无响应，AI 注入输入放行）' }
if ($BlockTouchpad) {
    if ([Touchpad]::UseDeviceMode) { Write-Host '  屏蔽触控板 : 开启（设备级禁用：指针 + 三指/四指手势全部失效，解锁自动恢复）' }
    else { Write-Host '  屏蔽触控板 : 开启（注册表开关：对三指手势可能无效，建议配置 -SetupTouchpadDevice）' }
}
if ($RemoteDetect) {
    if ($RemoteHideOverlay) { Write-Host "  远程控制   : 开启（检测到 $RemoteProcesses 被控时自动收起遮罩，断开 ${RemoteEndDelaySec}s 后自动重新盖上）" }
    else { Write-Host "  远程控制   : 开启（检测到 $RemoteProcesses 被控时放行鼠标键盘，遮罩保持）" }
}
if ($AntiBurn) { Write-Host '  防烧屏     : 开启（文字/画面每 20 秒轻微漂移 + 背景亮度微变）' }
if ($HideConsole) { Write-Host '  隐藏窗口   : 开启（控制台窗口即将隐藏）' }
Write-Host '  托盘图标   : 双击切换，右键退出'
Write-Host '  运行日志   : 隐私屏日志.txt（记录钩子/触控板等是否生效，排查用）'
Write-Host ''
Write-Host '紧急退出：Ctrl+Alt+Del -> 任务管理器 -> 结束 Windows PowerShell（该组合键不受屏蔽影响）'
Write-Host ''
Write-Host '原理：遮罩窗口设置了 WDA_EXCLUDEFROMCAPTURE —— 物理屏幕上可见，'
Write-Host '      但会被 Windows 从软件截图里剔除，AI 截图看到的是真实桌面。'
Write-Host ''

if ($HideConsole) {
    [Native]::ShowWindow([Native]::GetConsoleWindow(), 0) | Out-Null
}

# 启动自愈：上次若被强杀，触控板可能还停在禁用状态，这里先恢复
if ([Touchpad]::UseDeviceMode -and [Touchpad]::DeviceModeConfigured()) {
    $st = ''
    if (-not [Touchpad]::DeviceUsable([ref]$st)) {
        Write-Host "[隐私屏] 触控板当前不可用（$st），正在恢复..."
        if ([Touchpad]::DeviceEnable()) { Write-Host '[隐私屏] 触控板已恢复可用。' }
        else { Write-Warning '[隐私屏] 恢复失败，请运行 恢复触控板.cmd。' }
    }
}

[PrivacyEngine]::Start($StartHidden.IsPresent)
