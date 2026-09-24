#requires -Version 5.1
<#
  隐私屏 - 输入与远程控制诊断 (诊断.ps1)
 ----------------------------------------------------------------------------
  目的：一次性采集"真实操作时"的底层信号，用来确定两件事：
    1) 三指/四指手势到底以什么形式送达系统（键鼠事件？注入按键？还是 shell 内部处理）
       —— 决定手势能不能用钩子屏蔽，还是必须禁用触控板设备
    2) 向日葵被控时，机器上有什么稳定特征（进程/窗口/连接/UDP）
       —— 决定"远程会话自动检测"的判据

  用法：双击 诊断.cmd（会显示操作提示），按提示完成三个阶段即可。
  输出：诊断日志.txt（与脚本同目录），跑完发我 / 我直接读。

  说明：本脚本只监听、不拦截任何输入；请在运行前先敲密码解开遮罩（隐私屏程序可以留着）。
#>

[CmdletBinding()]
param(
    [int]$IdleSec = 20,
    [int]$ActiveSec = 60,
    [int]$AfterSec = 20,
    [switch]$CompileOnly
)

$ErrorActionPreference = 'Stop'

$src = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

public static class DiagLog
{
    private static string _path = "";
    private static object _lock = new object();

    public static void Init(string path) { _path = path; }

    public static void W(string s)
    {
        string line = DateTime.Now.ToString("HH:mm:ss.fff") + "  " + s;
        lock (_lock)
        {
            try { Console.WriteLine(line); } catch { }
            try { File.AppendAllText(_path, line + "\r\n", Encoding.UTF8); } catch { }
        }
    }

    public static void Phase(string s) { W(""); W("================ 阶段：" + s + " ================"); }
}

public static class DNative
{
    public const int WH_KEYBOARD_LL = 13;
    public const int WH_MOUSE_LL = 14;
    public const int WM_INPUT = 0x00FF;
    public const uint LLKHF_INJECTED = 0x10;
    public const uint LLMHF_INJECTED = 0x01;

    public const uint RID_INPUT = 0x10000003;
    public const uint RIDI_DEVICENAME = 0x20000007;
    public const uint RIDEV_INPUTSINK = 0x00000100;
    public const int RIM_TYPEMOUSE = 0;
    public const int RIM_TYPEKEYBOARD = 1;

    public const int AF_INET = 2;
    public const int TCP_TABLE_OWNER_PID_ALL = 5;
    public const int UDP_TABLE_OWNER_PID = 1;

    [DllImport("user32.dll")]
    public static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);
    [DllImport("user32.dll")]
    public static extern IntPtr SetWindowsHookEx(int idHook, LowLevelMouseProc lpfn, IntPtr hMod, uint dwThreadId);
    [DllImport("user32.dll")]
    public static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    public delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);
    public delegate IntPtr LowLevelMouseProc(int nCode, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct KBDLLHOOKSTRUCT { public uint vkCode; public uint scanCode; public uint flags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)]
    public struct MSLLHOOKSTRUCT { public int ptX; public int ptY; public uint mouseData; public uint flags; public uint time; public IntPtr dwExtraInfo; }

    [DllImport("user32.dll")]
    public static extern bool RegisterRawInputDevices(RAWINPUTDEVICE[] devices, uint numDevices, uint size);
    [DllImport("user32.dll")]
    public static extern uint GetRawInputData(IntPtr hRawInput, uint command, IntPtr data, ref uint size, uint headerSize);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern uint GetRawInputDeviceInfo(IntPtr hDevice, uint command, IntPtr data, ref uint size);

    [StructLayout(LayoutKind.Sequential)]
    public struct RAWINPUTDEVICE { public ushort usUsagePage; public ushort usUsage; public uint dwFlags; public IntPtr hwndTarget; }
    [StructLayout(LayoutKind.Sequential)]
    public struct RAWINPUTHEADER { public uint dwType; public uint dwSize; public IntPtr hDevice; public IntPtr wParam; }

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

    [DllImport("iphlpapi.dll", SetLastError = true)]
    public static extern uint GetExtendedTcpTable(IntPtr pTcpTable, ref int pdwSize, bool bOrder, int ulAf, int tableClass, uint reserved);
    [DllImport("iphlpapi.dll", SetLastError = true)]
    public static extern uint GetExtendedUdpTable(IntPtr pUdpTable, ref int pdwSize, bool bOrder, int ulAf, int tableClass, uint reserved);

    [StructLayout(LayoutKind.Sequential)]
    public struct MIB_TCPROW_OWNER_PID { public uint state; public uint localAddr; public uint localPort; public uint remoteAddr; public uint remotePort; public uint owningPid; }
    [StructLayout(LayoutKind.Sequential)]
    public struct MIB_UDPROW_OWNER_PID { public uint localAddr; public uint localPort; public uint owningPid; }
}

public class DiagForm : Form
{
    private List<int> _pids = new List<int>();
    private IntPtr _kbHook = IntPtr.Zero;
    private IntPtr _mouseHook = IntPtr.Zero;
    private DNative.LowLevelKeyboardProc _kbProc;
    private DNative.LowLevelMouseProc _mouseProc;
    private System.Windows.Forms.Timer _timer;
    private int _mouseMoves = 0, _keys = 0, _mouseButtons = 0;
    private Dictionary<IntPtr, string> _devCache = new Dictionary<IntPtr, string>();
    private string _lastWindowSig = "";

    public static string ProcessList = "AweSun,awesun_guard,SunloginClient,SunloginRemote";

    public DiagForm()
    {
        ShowInTaskbar = false;
        WindowState = FormWindowState.Minimized;
        Opacity = 0;
        _kbProc = KbProc;
        _mouseProc = MouseProc;
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        // 钩子必须装在有消息循环的这个线程上
        _kbHook = DNative.SetWindowsHookEx(DNative.WH_KEYBOARD_LL, _kbProc, IntPtr.Zero, 0);
        _mouseHook = DNative.SetWindowsHookEx(DNative.WH_MOUSE_LL, _mouseProc, IntPtr.Zero, 0);
        DiagLog.W("键盘钩子=" + (_kbHook != IntPtr.Zero) + "  鼠标钩子=" + (_mouseHook != IntPtr.Zero));
        DNative.RAWINPUTDEVICE[] devs = new DNative.RAWINPUTDEVICE[2];
        devs[0].usUsagePage = 0x01; devs[0].usUsage = 0x06; devs[0].dwFlags = DNative.RIDEV_INPUTSINK; devs[0].hwndTarget = Handle;
        devs[1].usUsagePage = 0x01; devs[1].usUsage = 0x02; devs[1].dwFlags = DNative.RIDEV_INPUTSINK; devs[1].hwndTarget = Handle;
        bool ok = DNative.RegisterRawInputDevices(devs, 2, (uint)Marshal.SizeOf(typeof(DNative.RAWINPUTDEVICE)));
        DiagLog.W("Raw Input 注册=" + ok + "（用于识别输入来自哪个设备）");
        _timer = new System.Windows.Forms.Timer();
        _timer.Interval = 1000;
        _timer.Tick += delegate { Sample(); };
        _timer.Start();
    }

    public void Start()
    {
        Application.Run(this);
    }

    private string DeviceName(IntPtr hDevice)
    {
        if (hDevice == IntPtr.Zero) return "none";
        if (_devCache.ContainsKey(hDevice)) return _devCache[hDevice];
        string name = "unknown";
        try
        {
            uint size = 0;
            DNative.GetRawInputDeviceInfo(hDevice, DNative.RIDI_DEVICENAME, IntPtr.Zero, ref size);
            if (size > 0)
            {
                IntPtr buf = Marshal.AllocHGlobal((int)size * 2);
                try
                {
                    if (DNative.GetRawInputDeviceInfo(hDevice, DNative.RIDI_DEVICENAME, buf, ref size) > 0)
                        name = Marshal.PtrToStringUni(buf);
                }
                finally { Marshal.FreeHGlobal(buf); }
            }
        }
        catch { }
        _devCache[hDevice] = name;
        return name;
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == DNative.WM_INPUT)
        {
            try
            {
                uint size = 0;
                DNative.GetRawInputData(m.LParam, DNative.RID_INPUT, IntPtr.Zero, ref size, (uint)Marshal.SizeOf(typeof(DNative.RAWINPUTHEADER)));
                if (size > 0)
                {
                    IntPtr buf = Marshal.AllocHGlobal((int)size);
                    try
                    {
                        if (DNative.GetRawInputData(m.LParam, DNative.RID_INPUT, buf, ref size, (uint)Marshal.SizeOf(typeof(DNative.RAWINPUTHEADER))) == size)
                        {
                            DNative.RAWINPUTHEADER hdr = (DNative.RAWINPUTHEADER)Marshal.PtrToStructure(buf, typeof(DNative.RAWINPUTHEADER));
                            // 只在第一次见到某个设备时记录，避免刷屏
                            if (!_devCache.ContainsKey(hdr.hDevice))
                            {
                                string n = DeviceName(hdr.hDevice);
                                DiagLog.W("[设备] type=" + (hdr.dwType == DNative.RIM_TYPEKEYBOARD ? "键盘" : "鼠标") + "  " + n);
                            }
                        }
                    }
                    finally { Marshal.FreeHGlobal(buf); }
                }
            }
            catch { }
        }
        base.WndProc(ref m);
    }

    private IntPtr KbProc(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            int msg = (int)wParam;
            if (msg == 0x100 || msg == 0x104)
            {
                DNative.KBDLLHOOKSTRUCT k = (DNative.KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(DNative.KBDLLHOOKSTRUCT));
                _keys++;
                DiagLog.W("[按键] vk=0x" + k.vkCode.ToString("X2") + " injected=" + ((k.flags & DNative.LLKHF_INJECTED) != 0)
                    + " extra=0x" + k.dwExtraInfo.ToInt64().ToString("X") + " scan=" + k.scanCode);
            }
        }
        return DNative.CallNextHookEx(_kbHook, nCode, wParam, lParam);
    }

    private IntPtr MouseProc(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            int msg = (int)wParam;
            DNative.MSLLHOOKSTRUCT m = (DNative.MSLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(DNative.MSLLHOOKSTRUCT));
            if (msg == 0x200) { _mouseMoves++; }
            else
            {
                _mouseButtons++;
                DiagLog.W("[鼠标] msg=0x" + msg.ToString("X") + " injected=" + ((m.flags & DNative.LLMHF_INJECTED) != 0)
                    + " extra=0x" + m.dwExtraInfo.ToInt64().ToString("X") + " data=" + m.mouseData);
            }
        }
        return DNative.CallNextHookEx(_mouseHook, nCode, wParam, lParam);
    }

    private List<int> ToolPids()
    {
        List<int> pids = new List<int>();
        foreach (string name in ProcessList.Split(','))
        {
            string t = name.Trim();
            if (t.Length == 0) continue;
            try
            {
                foreach (Process p in Process.GetProcessesByName(t))
                {
                    try { pids.Add(p.Id); } catch { }
                    try { p.Dispose(); } catch { }
                }
            }
            catch { }
        }
        return pids;
    }

    private void Sample()
    {
        try
        {
            List<int> pids = ToolPids();
            List<string> winInfo = new List<string>();
            string sig = "";
            if (pids.Count > 0)
            {
                DNative.EnumWindows(delegate(IntPtr h, IntPtr data)
                {
                    uint pid;
                    DNative.GetWindowThreadProcessId(h, out pid);
                    if (!pids.Contains((int)pid)) return true;
                    bool vis = DNative.IsWindowVisible(h);
                    StringBuilder cls = new StringBuilder(256);
                    DNative.GetClassName(h, cls, 256);
                    StringBuilder title = new StringBuilder(256);
                    DNative.GetWindowText(h, title, 256);
                    string s = "pid=" + pid + " vis=" + (vis ? 1 : 0) + " class='" + cls + "' title='" + title + "'";
                    winInfo.Add(s);
                    if (vis) sig += s + ";";
                    return true;
                }, IntPtr.Zero);
            }

            int tcp = 0, udp = 0;
            List<string> endpoints = new List<string>();
            try
            {
                int size = 0;
                DNative.GetExtendedTcpTable(IntPtr.Zero, ref size, false, DNative.AF_INET, DNative.TCP_TABLE_OWNER_PID_ALL, 0);
                if (size > 0)
                {
                    IntPtr buf = Marshal.AllocHGlobal(size);
                    try
                    {
                        if (DNative.GetExtendedTcpTable(buf, ref size, false, DNative.AF_INET, DNative.TCP_TABLE_OWNER_PID_ALL, 0) == 0)
                        {
                            int rows = Marshal.ReadInt32(buf);
                            int rowSize = Marshal.SizeOf(typeof(DNative.MIB_TCPROW_OWNER_PID));
                            long b = buf.ToInt64() + 4;
                            for (int i = 0; i < rows; i++)
                            {
                                DNative.MIB_TCPROW_OWNER_PID r = (DNative.MIB_TCPROW_OWNER_PID)Marshal.PtrToStructure(new IntPtr(b + i * rowSize), typeof(DNative.MIB_TCPROW_OWNER_PID));
                                if (!pids.Contains((int)r.owningPid)) continue;
                                if (r.state == 5)
                                {
                                    uint ra = r.remoteAddr;
                                    if ((ra & 0xFF) != 127)
                                    {
                                        tcp++;
                                        endpoints.Add("TCP pid=" + r.owningPid + " -> " + (ra & 0xFF) + "." + ((ra >> 8) & 0xFF) + "." + ((ra >> 16) & 0xFF) + "." + ((ra >> 24) & 0xFF) + ":" + (((r.remotePort & 0xFF) << 8) | ((r.remotePort >> 8) & 0xFF)));
                                    }
                                }
                            }
                        }
                    }
                    finally { Marshal.FreeHGlobal(buf); }
                }
            }
            catch { }
            try
            {
                int size = 0;
                DNative.GetExtendedUdpTable(IntPtr.Zero, ref size, false, DNative.AF_INET, DNative.UDP_TABLE_OWNER_PID, 0);
                if (size > 0)
                {
                    IntPtr buf = Marshal.AllocHGlobal(size);
                    try
                    {
                        if (DNative.GetExtendedUdpTable(buf, ref size, false, DNative.AF_INET, DNative.UDP_TABLE_OWNER_PID, 0) == 0)
                        {
                            int rows = Marshal.ReadInt32(buf);
                            int rowSize = Marshal.SizeOf(typeof(DNative.MIB_UDPROW_OWNER_PID));
                            long b = buf.ToInt64() + 4;
                            for (int i = 0; i < rows; i++)
                            {
                                DNative.MIB_UDPROW_OWNER_PID r = (DNative.MIB_UDPROW_OWNER_PID)Marshal.PtrToStructure(new IntPtr(b + i * rowSize), typeof(DNative.MIB_UDPROW_OWNER_PID));
                                if (pids.Contains((int)r.owningPid)) udp++;
                            }
                        }
                    }
                    finally { Marshal.FreeHGlobal(buf); }
                }
            }
            catch { }

            DiagLog.W("[采样] 进程=" + pids.Count + " 可见窗口=" + (sig.Length > 0 ? "有" : "无") + " TCP=" + tcp + " UDP=" + udp
                + " 鼠标移动/秒=" + _mouseMoves + " 鼠标按键/秒=" + _mouseButtons + " 按键/秒=" + _keys);

            if (sig != _lastWindowSig)
            {
                _lastWindowSig = sig;
                if (sig.Length > 0)
                {
                    DiagLog.W("[可见窗口出现/变化]");
                    foreach (string w in winInfo) if (w.IndexOf("vis=1") >= 0) DiagLog.W("    " + w);
                }
                else
                {
                    DiagLog.W("[可见窗口全部消失]");
                }
            }
            if (endpoints.Count > 0)
            {
                foreach (string e in endpoints) DiagLog.W("    " + e);
            }

            _mouseMoves = 0; _mouseButtons = 0; _keys = 0;
        }
        catch (Exception ex) { DiagLog.W("[采样异常] " + ex.Message); }
    }
}
public static class DiagRunner
{
    private static DiagForm _form;

    public static void Start()
    {
        Thread t = new Thread(delegate()
        {
            _form = new DiagForm();
            Application.Run(_form);
        });
        t.IsBackground = true;
        t.SetApartmentState(ApartmentState.STA);
        t.Start();
    }
}
'@

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition $src -ReferencedAssemblies 'System.Windows.Forms', 'System.Drawing'

if ($CompileOnly) {
    Write-Host 'OK: 诊断脚本编译通过。'
    exit 0
}

$logPath = Join-Path $PSScriptRoot '诊断日志.txt'
Remove-Item -LiteralPath $logPath -ErrorAction SilentlyContinue
[DiagLog]::Init($logPath)

Write-Host ''
Write-Host '================ 隐私屏诊断 ================'
Write-Host '本脚本只监听、不拦截输入；请先解锁遮罩（隐私屏程序可以留着）。'
Write-Host "日志文件：$logPath"
Write-Host ''

[DiagLog]::W('诊断开始')
[DiagLog]::W('系统版本: ' + [Environment]::OSVersion.VersionString + ' build ' + [Environment]::OSVersion.Version.Build)

# 触控板 / 输入设备清单（为"设备级禁用触控板"做准备）
try {
    $devs = Get-PnpDevice -ErrorAction Stop | Where-Object { $_.Class -in @('Mouse', 'HIDClass') -and $_.FriendlyName -match '触控板|触摸板|touch ?pad|I2C HID|HID-compliant mouse|ELAN|Synaptics|Precision' }
    [DiagLog]::W('--- 触控板/输入设备候选 ---')
    foreach ($d in $devs) { [DiagLog]::W('  ' + $d.Status + ' | ' + $d.Class + ' | ' + $d.FriendlyName + ' | ' + $d.InstanceId) }
} catch {
    [DiagLog]::W('设备枚举失败（Get-PnpDevice 不可用）：' + $_.Exception.Message)
}

$form = $null
[DiagRunner]::Start()
Start-Sleep -Seconds 2

[DiagLog]::Phase("第 1 段：空闲基线（请不要碰触控板/鼠标键盘，也不要连接向日葵）")
Write-Host "第 1 段：空闲基线 - $IdleSec 秒，请什么都不要做..." -ForegroundColor Cyan
for ($i = $IdleSec; $i -gt 0; $i--) { Write-Host "`r  倒计时 $i 秒 " -NoNewline; Start-Sleep -Seconds 1 }
Write-Host ''

[DiagLog]::Phase("第 2 段：请用手机向日葵连接本机，然后做这些操作（顺序不限，每样做 2~3 次）")
Write-Host ''
Write-Host '第 2 段（重点）：请现在用手机向日葵连接本机，然后依次做：' -ForegroundColor Yellow
Write-Host '  1. 远程移动鼠标、点几下、滚动' -ForegroundColor Yellow
Write-Host '  2. 远程敲几个字符（比如 aaabbb）' -ForegroundColor Yellow
Write-Host '  3. 本机触控板：三指上滑(任务视图)、三指下滑、三指左右滑、三指轻触、四指轻触' -ForegroundColor Yellow
Write-Host "  共 $ActiveSec 秒，做完保持连接别断开" -ForegroundColor Yellow
for ($i = $ActiveSec; $i -gt 0; $i--) { Write-Host "`r  倒计时 $i 秒 " -NoNewline; Start-Sleep -Seconds 1 }
Write-Host ''

[DiagLog]::Phase("第 3 段：请现在断开手机上的向日葵远控")
Write-Host "第 3 段：请现在断开手机向日葵 - $AfterSec 秒" -ForegroundColor Cyan
for ($i = $AfterSec; $i -gt 0; $i--) { Write-Host "`r  倒计时 $i 秒 " -NoNewline; Start-Sleep -Seconds 1 }
Write-Host ''

[DiagLog]::W('诊断结束')
Write-Host ''
Write-Host "采集完成：$logPath" -ForegroundColor Green
Write-Host '把 诊断日志.txt 发我即可。' -ForegroundColor Green
