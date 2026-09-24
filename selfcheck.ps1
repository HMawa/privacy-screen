#requires -Version 5.1
<#
=============================================================================
 隐私屏 - 截图豁免双路径实测 (selfcheck.ps1)
 ----------------------------------------------------------------------------
 目的：实测本机上 GDI 与 DXGI 两条软件截图路径对
       WDA_EXCLUDEFROMCAPTURE 遮罩的真实行为。

 过程（全程约 6 秒，屏幕右下角会出现两次粉色色块，请确认你能看到它）：
   第 1 阶段  基线：不显示任何窗口，抓取右下角区域颜色。
   第 2 阶段  对照：显示粉色测试窗（不设截图豁免）→ 截图应看到粉色，
              以此验证抓屏代码本身工作正常（若看不到粉色说明该路径不可用）。
   第 3 阶段  豁免：给同一窗口设置 WDA_EXCLUDEFROMCAPTURE → 截图应看到
              第 1 阶段的基线（背后的真实桌面）。

 判定（对每条路径）：
   对照≈粉色 且 豁免≈基线  => 豁免生效：AI 截图看到真实桌面，安全。
   对照≈粉色 且 豁免≈粉色  => 豁免失败：该路径会截到遮罩。
   对照≈粉色 且 豁免≈黑块  => 豁免失败：该路径下遮罩区域变黑。
   对照≠粉色              => 该路径抓屏不可用，无法判定。

 注意：DXGI 每个输出同一时刻只允许一个程序复制；若 AI 工具正在用 DXGI
       抓屏，本测试的 DXGI 部分会报告不可用，先关掉它再测。

 用法：powershell -NoProfile -ExecutionPolicy Bypass -File .\selfcheck.ps1
       powershell -NoProfile -ExecutionPolicy Bypass -File .\selfcheck.ps1 -BlockMs 2000
=============================================================================
#>

[CmdletBinding()]
param(
    [int]$BlockMs = 1500,
    [switch]$CompileOnly,
    [switch]$DxgiDiag
)

$ErrorActionPreference = 'Stop'

$src = @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

public static class SCNative
{
    public const uint WDA_EXCLUDEFROMCAPTURE = 0x11;

    public const int WS_EX_TOPMOST = 0x00000008;
    public const int WS_EX_TRANSPARENT = 0x00000020;
    public const int WS_EX_TOOLWINDOW = 0x00000080;
    public const int WS_EX_NOACTIVATE = 0x08000000;

    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

    [DllImport("user32.dll")]
    public static extern bool SetWindowDisplayAffinity(IntPtr hWnd, uint dwAffinity);
}

public class TestWindow : Form
{
    private bool _affinity;

    public TestWindow(Rectangle bounds, bool affinity)
    {
        _affinity = affinity;
        Bounds = bounds;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;
        BackColor = Color.FromArgb(233, 30, 99);
        Text = "隐私屏自检";
    }

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= SCNative.WS_EX_TOPMOST | SCNative.WS_EX_TOOLWINDOW | SCNative.WS_EX_NOACTIVATE | SCNative.WS_EX_TRANSPARENT;
            return cp;
        }
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        if (_affinity) SCNative.SetWindowDisplayAffinity(Handle, SCNative.WDA_EXCLUDEFROMCAPTURE);
    }
}

public static class GdiSampler
{
    public static Color Sample(Rectangle r)
    {
        using (Bitmap bmp = new Bitmap(r.Width, r.Height))
        {
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.CopyFromScreen(r.X, r.Y, 0, 0, new Size(r.Width, r.Height));
            }
            int rs = 0, gs = 0, bs = 0, n = 0;
            for (int y = 20; y < r.Height; y += 30)
            {
                for (int x = 20; x < r.Width; x += 30)
                {
                    Color c = bmp.GetPixel(x, y);
                    rs += c.R; gs += c.G; bs += c.B; n++;
                }
            }
            return Color.FromArgb(rs / n, gs / n, bs / n);
        }
    }
}

// ---------- DXGI Desktop Duplication 最小互操作 ----------

public static class DxgiRaw
{
    [DllImport("d3d11.dll")]
    public static extern int D3D11CreateDevice(
        IntPtr pAdapter, int DriverType, IntPtr Software, uint Flags,
        int[] pFeatureLevels, uint FeatureLevels, uint SDKVersion,
        out IntPtr ppDevice, out int pFeatureLevel, out IntPtr ppImmediateContext);

    [DllImport("dxgi.dll")]
    public static extern int CreateDXGIFactory1(ref Guid riid, out IntPtr ppFactory);
}

[ComImport, Guid("770aae78-f26f-4dba-a829-253c83d1b387"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IDXGIFactory1
{
    void SetPrivateData(ref Guid name, uint size, IntPtr data);
    void SetPrivateDataInterface(ref Guid name, [MarshalAs(UnmanagedType.IUnknown)] object data);
    void GetPrivateData(ref Guid name, ref uint size, IntPtr data);
    void GetParent(ref Guid riid, out IntPtr parent);
    [PreserveSig]
    int EnumAdapters(uint index, out IDXGIAdapter adapter);
    void MakeWindowAssociation(IntPtr window, uint flags);
    void GetWindowAssociation(out IntPtr window);
    void CreateSwapChain(IntPtr device, IntPtr desc, out IntPtr swapChain);
    [PreserveSig]
    int EnumAdapters1(uint index, out IDXGIAdapter1 adapter);
    [return: MarshalAs(UnmanagedType.Bool)] bool IsCurrent();
}

[ComImport, Guid("2411e7e1-12ac-4ccf-bd14-9798e8534dc0"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IDXGIAdapter
{
    void SetPrivateData(ref Guid name, uint size, IntPtr data);
    void SetPrivateDataInterface(ref Guid name, [MarshalAs(UnmanagedType.IUnknown)] object data);
    void GetPrivateData(ref Guid name, ref uint size, IntPtr data);
    void GetParent(ref Guid riid, out IntPtr parent);
    [PreserveSig]
    int EnumOutputs(uint index, out IDXGIOutput output);
    void GetDesc(out IntPtr desc);
    void CheckInterfaceSupport(ref Guid name, out long version);
}

[ComImport, Guid("29038f61-3839-4626-91fd-086879011a05"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IDXGIAdapter1
{
    void SetPrivateData(ref Guid name, uint size, IntPtr data);
    void SetPrivateDataInterface(ref Guid name, [MarshalAs(UnmanagedType.IUnknown)] object data);
    void GetPrivateData(ref Guid name, ref uint size, IntPtr data);
    void GetParent(ref Guid riid, out IntPtr parent);
    [PreserveSig]
    int EnumOutputs(uint index, out IDXGIOutput output);
    void GetDesc(out IntPtr desc);
    void CheckInterfaceSupport(ref Guid name, out long version);
    void GetDesc1(out IntPtr desc);
}

[ComImport, Guid("ae02eedb-c735-4690-8d52-5a8dc20213aa"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IDXGIOutput
{
    void SetPrivateData(ref Guid name, uint size, IntPtr data);
    void SetPrivateDataInterface(ref Guid name, [MarshalAs(UnmanagedType.IUnknown)] object data);
    void GetPrivateData(ref Guid name, ref uint size, IntPtr data);
    void GetParent(ref Guid riid, out IntPtr parent);
    void GetDesc(out DXGI_OUTPUT_DESC desc);
    void GetDisplayModeList(uint format, uint flags, ref uint count, IntPtr descs);
    void FindClosestMatchingMode(IntPtr mode, IntPtr closest, IntPtr device);
    void WaitForVBlank();
    void TakeOwnership(IntPtr device, [MarshalAs(UnmanagedType.Bool)] bool exclusive);
    void GetGammaControl(out IntPtr caps);
    void SetGammaControl(IntPtr caps);
    void GetGammaControlCapabilities(out IntPtr caps);
    void SetDisplaySurface(IntPtr surface);
    void GetDisplaySurfaceData(IntPtr surface);
    void GetFrameStatistics(out IntPtr stats);
}

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct DXGI_OUTPUT_DESC
{
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
    public int DesktopLeft;
    public int DesktopTop;
    public int DesktopRight;
    public int DesktopBottom;
    public int AttachedToDesktop;
    public uint Rotation;
    public IntPtr Monitor;
}

[ComImport, Guid("00cddea8-939b-4b83-a340-a685226666cc"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IDXGIOutput1
{
    void SetPrivateData(ref Guid name, uint size, IntPtr data);
    void SetPrivateDataInterface(ref Guid name, [MarshalAs(UnmanagedType.IUnknown)] object data);
    void GetPrivateData(ref Guid name, ref uint size, IntPtr data);
    void GetParent(ref Guid riid, out IntPtr parent);
    void GetDesc(out DXGI_OUTPUT_DESC desc);
    void GetDisplayModeList(uint format, uint flags, ref uint count, IntPtr descs);
    void FindClosestMatchingMode(IntPtr mode, IntPtr closest, IntPtr device);
    void WaitForVBlank();
    void TakeOwnership(IntPtr device, [MarshalAs(UnmanagedType.Bool)] bool exclusive);
    void GetGammaControl(out IntPtr caps);
    void SetGammaControl(IntPtr caps);
    void GetGammaControlCapabilities(out IntPtr caps);
    void SetDisplaySurface(IntPtr surface);
    void GetDisplaySurfaceData(IntPtr surface);
    void GetFrameStatistics(out IntPtr stats);
    void GetDisplayModeList1(uint format, uint flags, ref uint count, IntPtr descs);
    void FindClosestMatchingMode1(IntPtr mode, IntPtr closest, IntPtr device);
    void GetDisplaySurfaceData1(IntPtr surface);
    [PreserveSig]
    int DuplicateOutput(IntPtr device, out IDXGIOutputDuplication duplication);
}

[ComImport, Guid("191cfac3-a341-470d-b26e-a864f428319c"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IDXGIOutputDuplication
{
    void GetDesc(out IntPtr desc);
    [PreserveSig]
    int AcquireNextFrame(uint timeout, out DXGI_OUTDUPL_FRAME_INFO frameInfo, out IntPtr desktopResource);
    [PreserveSig]
    int GetFrameDirtyRects(uint size, IntPtr rects, out uint required);
    [PreserveSig]
    int GetFrameMoveRects(uint size, IntPtr rects, out uint required);
    [PreserveSig]
    int GetFramePointerShape(uint size, IntPtr shape, out uint required, out IntPtr pointerShape);
    [PreserveSig]
    int MapDesktopSurface(out IntPtr mapped);
    [PreserveSig]
    int UnMapDesktopSurface();
    [PreserveSig]
    int ReleaseFrame();
}

[StructLayout(LayoutKind.Sequential)]
public struct DXGI_OUTDUPL_FRAME_INFO
{
    public long LastPresentTime;
    public long LastMouseUpdateTime;
    public uint AccumulatedFrames;
    public int RectsCoalesced;
    public int ProtectedContentMaskedOut;
    public DXGI_OUTDUPL_POINTER_POSITION PointerPosition;
    public uint TotalMetadataBufferSize;
    public uint PointerShapeBufferSize;
}

[StructLayout(LayoutKind.Sequential)]
public struct DXGI_OUTDUPL_POINTER_POSITION
{
    public int X;
    public int Y;
    public int Visible;
}

[ComImport, Guid("db6f6ddb-ac77-4e88-8253-819df9bbf140"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ID3D11Device
{
    void CreateBuffer(ref int desc, IntPtr initialData, out IntPtr buffer);
    void CreateTexture1D(ref int desc, IntPtr initialData, out IntPtr texture);
    void CreateTexture2D(ref D3D11_TEXTURE2D_DESC desc, IntPtr initialData, out IntPtr texture);
}

[StructLayout(LayoutKind.Sequential)]
public struct D3D11_TEXTURE2D_DESC
{
    public uint Width;
    public uint Height;
    public uint MipLevels;
    public uint ArraySize;
    public int Format;
    public uint SampleCount;
    public uint SampleQuality;
    public uint Usage;
    public uint BindFlags;
    public uint CPUAccessFlags;
    public uint MiscFlags;
}

[ComImport, Guid("c0bfa96c-e089-44fb-8eaf-26f8796190da"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ID3D11DeviceContext
{
    void VSSetConstantBuffers(uint a, uint b, IntPtr c);
    void PSSetShaderResources(uint a, uint b, IntPtr c);
    void PSSetShader(IntPtr a, IntPtr b, uint c);
    void PSSetSamplers(uint a, uint b, IntPtr c);
    void VSSetShader(IntPtr a, IntPtr b, uint c);
    void DrawIndexed(uint a, uint b, int c);
    void Draw(uint a, uint b);
    void Map(IntPtr resource, uint subresource, uint mapType, uint mapFlags, out D3D11_MAPPED_SUBRESOURCE mapped);
    void Unmap(IntPtr resource, uint subresource);
    void PSSetConstantBuffers(uint a, uint b, IntPtr c);
    void IASetInputLayout(IntPtr a);
    void IASetVertexBuffers(uint a, uint b, IntPtr c, IntPtr d, IntPtr e);
    void IASetIndexBuffer(IntPtr a, int b, uint c);
    void DrawIndexedInstanced(uint a, uint b, uint c, int d, uint e);
    void DrawInstanced(uint a, uint b, uint c, uint d);
    void GSSetConstantBuffers(uint a, uint b, IntPtr c);
    void GSSetShader(IntPtr a, IntPtr b, uint c);
    void IASetPrimitiveTopology(uint a);
    void VSSetShaderResources(uint a, uint b, IntPtr c);
    void VSSetSamplers(uint a, uint b, IntPtr c);
    void Begin(IntPtr a);
    void End(IntPtr a);
    void GetData(IntPtr a, IntPtr b, uint c);
    void SetPredication(IntPtr a, int b);
    void GSSetShaderResources(uint a, uint b, IntPtr c);
    void GSSetSamplers(uint a, uint b, IntPtr c);
    void OMSetRenderTargets(uint a, IntPtr b, IntPtr c);
    void OMSetRenderTargetsAndUnorderedAccessViews(uint a, IntPtr b, IntPtr c, uint d, uint e, IntPtr f);
    void OMSetBlendState(IntPtr a, IntPtr b, uint c);
    void OMSetDepthStencilState(IntPtr a, uint b);
    void SOSetTargets(uint a, IntPtr b, IntPtr c);
    void DrawAuto();
    void DrawIndexedInstancedIndirect(IntPtr a, uint b);
    void DrawInstancedIndirect(IntPtr a, uint b);
    void Dispatch(uint a, uint b, uint c);
    void DispatchIndirect(IntPtr a, uint b);
    void RSSetState(IntPtr a);
    void RSSetViewports(uint a, IntPtr b);
    void RSSetScissorRects(uint a, IntPtr b);
    void CopySubresourceRegion(IntPtr a, uint b, uint c, uint d, uint e, IntPtr f, uint g, uint h, uint i);
    void CopyResource(IntPtr dst, IntPtr src);
}

[ComImport, Guid("6f15aaf2-d208-4e89-9ab4-489535d34f9c"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ID3D11Texture2D
{
    void GetType(out uint type);
    void SetEvictionPriority(uint priority);
    void GetEvictionPriority(out uint priority);
    void GetDesc(out D3D11_TEXTURE2D_DESC desc);
}

[StructLayout(LayoutKind.Sequential)]
public struct D3D11_MAPPED_SUBRESOURCE
{
    public IntPtr pData;
    public uint RowPitch;
    public uint DepthPitch;
}

public static class DxgiSampler
{
    public static bool TrySample(int x, int y, out Color color, out string error)
    {
        color = Color.Black;
        error = "";
        IntPtr factoryPtr = IntPtr.Zero;
        IntPtr devicePtr = IntPtr.Zero;
        IntPtr ctxPtr = IntPtr.Zero;
        IDXGIOutputDuplication dup = null;
        try
        {
            Guid factoryGuid = typeof(IDXGIFactory1).GUID;
            int hr = DxgiRaw.CreateDXGIFactory1(ref factoryGuid, out factoryPtr);
            if (hr != 0) { error = "CreateDXGIFactory1 失败 0x" + hr.ToString("X8"); return false; }
            IDXGIFactory1 factory = (IDXGIFactory1)Marshal.GetObjectForIUnknown(factoryPtr);

            IDXGIOutput target = null;
            DXGI_OUTPUT_DESC targetDesc = new DXGI_OUTPUT_DESC();
            bool found = false;
            StringBuilder diag = new StringBuilder();
            for (uint a = 0; a < 4 && !found; a++)
            {
                IDXGIAdapter1 adapter;
                int hra = factory.EnumAdapters1(a, out adapter);
                diag.Append(" adapter" + a + ":hr=0x" + hra.ToString("X8"));
                if (hra != 0) break;
                for (uint i = 0; i < 8; i++)
                {
                    IDXGIOutput output;
                    int hro = adapter.EnumOutputs(i, out output);
                    if (hro != 0 || output == null) { diag.Append(" out" + i + ":hr=0x" + hro.ToString("X8")); break; }
                    DXGI_OUTPUT_DESC desc;
                    output.GetDesc(out desc);
                    diag.Append(" out" + i + ":[" + desc.DesktopLeft + "," + desc.DesktopTop + "-" + desc.DesktopRight + "," + desc.DesktopBottom + "]att=" + desc.AttachedToDesktop + " '" + desc.DeviceName + "'");
                    if (desc.AttachedToDesktop != 0 &&
                        x >= desc.DesktopLeft && x < desc.DesktopRight &&
                        y >= desc.DesktopTop && y < desc.DesktopBottom)
                    {
                        target = output;
                        targetDesc = desc;
                        found = true;
                        break;
                    }
                }
                diag.Append(";");
            }
            if (!found) { error = "未找到包含测试点(" + x + "," + y + ")的显示器输出。" + diag.ToString(); return false; }

            IDXGIOutput1 output1 = (IDXGIOutput1)target;

            int[] levels = new int[] { 0xB000, 0xA100, 0xA000 };
            int level = 0;
            hr = DxgiRaw.D3D11CreateDevice(IntPtr.Zero, 1, IntPtr.Zero, 0x20, levels, 3, 7, out devicePtr, out level, out ctxPtr);
            if (hr != 0)
            {
                hr = DxgiRaw.D3D11CreateDevice(IntPtr.Zero, 5, IntPtr.Zero, 0x20, levels, 3, 7, out devicePtr, out level, out ctxPtr);
                if (hr != 0) { error = "D3D11CreateDevice 失败 0x" + hr.ToString("X8"); return false; }
            }
            ID3D11Device device = (ID3D11Device)Marshal.GetObjectForIUnknown(devicePtr);
            ID3D11DeviceContext context = (ID3D11DeviceContext)Marshal.GetObjectForIUnknown(ctxPtr);

            hr = output1.DuplicateOutput(devicePtr, out dup);
            if (hr != 0) { error = "DuplicateOutput 失败 0x" + hr.ToString("X8") + "（可能已有其他程序在抓屏）"; return false; }

            // 排空旧帧
            DXGI_OUTDUPL_FRAME_INFO fi;
            IntPtr res;
            int drain = dup.AcquireNextFrame(200, out fi, out res);
            if (drain == 0) { Marshal.Release(res); dup.ReleaseFrame(); }

            DXGI_OUTDUPL_FRAME_INFO frameInfo;
            IntPtr desktopResource;
            hr = dup.AcquireNextFrame(1500, out frameInfo, out desktopResource);
            if (hr != 0) { error = "AcquireNextFrame 失败 0x" + hr.ToString("X8"); return false; }

            try
            {
                object o = Marshal.GetObjectForIUnknown(desktopResource);
                ID3D11Texture2D texture = (ID3D11Texture2D)o;

                D3D11_TEXTURE2D_DESC sd = new D3D11_TEXTURE2D_DESC();
                sd.Width = (uint)(targetDesc.DesktopRight - targetDesc.DesktopLeft);
                sd.Height = (uint)(targetDesc.DesktopBottom - targetDesc.DesktopTop);
                sd.MipLevels = 1;
                sd.ArraySize = 1;
                sd.Format = 87; // DXGI_FORMAT_B8G8R8A8_UNORM
                sd.SampleCount = 1;
                sd.SampleQuality = 0;
                sd.Usage = 3; // D3D11_USAGE_STAGING
                sd.BindFlags = 0;
                sd.CPUAccessFlags = 0x20000; // D3D11_CPU_ACCESS_READ
                sd.MiscFlags = 0;

                IntPtr stagingPtr;
                device.CreateTexture2D(ref sd, IntPtr.Zero, out stagingPtr);
                try
                {
                    context.CopyResource(stagingPtr, desktopResource);
                    D3D11_MAPPED_SUBRESOURCE mapped;
                    context.Map(stagingPtr, 0, 1, 0, out mapped);
                    int px = x - targetDesc.DesktopLeft;
                    int py = y - targetDesc.DesktopTop;
                    int off = py * (int)mapped.RowPitch + px * 4;
                    int b = Marshal.ReadByte(mapped.pData, off);
                    int g = Marshal.ReadByte(mapped.pData, off + 1);
                    int r = Marshal.ReadByte(mapped.pData, off + 2);
                    context.Unmap(stagingPtr, 0);
                    color = Color.FromArgb(r, g, b);
                }
                finally
                {
                    Marshal.Release(stagingPtr);
                }
                return true;
            }
            finally
            {
                dup.ReleaseFrame();
                Marshal.Release(desktopResource);
            }
        }
        catch (Exception ex)
        {
            error = ex.GetType().Name + ": " + ex.Message;
            return false;
        }
        finally
        {
            if (dup != null) { try { Marshal.FinalReleaseComObject(dup); } catch { } }
            if (ctxPtr != IntPtr.Zero) Marshal.Release(ctxPtr);
            if (devicePtr != IntPtr.Zero) Marshal.Release(devicePtr);
            if (factoryPtr != IntPtr.Zero) Marshal.Release(factoryPtr);
        }
    }

    public static string Diag()
    {
        StringBuilder sb = new StringBuilder();
        IntPtr factoryPtr = IntPtr.Zero;
        try
        {
            Guid factoryGuid = typeof(IDXGIFactory1).GUID;
            int hr = DxgiRaw.CreateDXGIFactory1(ref factoryGuid, out factoryPtr);
            sb.AppendLine("CreateDXGIFactory1 hr=0x" + hr.ToString("X8"));
            if (hr != 0) return sb.ToString();
            IDXGIFactory1 factory = (IDXGIFactory1)Marshal.GetObjectForIUnknown(factoryPtr);
            for (uint a = 0; a < 4; a++)
            {
                IDXGIAdapter1 adapter;
                int hra = factory.EnumAdapters1(a, out adapter);
                sb.AppendLine("EnumAdapters1(" + a + ") hr=0x" + hra.ToString("X8"));
                if (hra != 0) break;
                for (uint i = 0; i < 8; i++)
                {
                    IDXGIOutput output;
                    int hro = adapter.EnumOutputs(i, out output);
                    if (hro != 0) { sb.AppendLine("  EnumOutputs(" + i + ") hr=0x" + hro.ToString("X8")); break; }
                    DXGI_OUTPUT_DESC desc;
                    output.GetDesc(out desc);
                    sb.AppendLine("  output" + i + ": " + desc.DeviceName + " rect=[" + desc.DesktopLeft + "," + desc.DesktopTop + "-" + desc.DesktopRight + "," + desc.DesktopBottom + "] attached=" + desc.AttachedToDesktop + " rotation=" + desc.Rotation);
                }
            }
            sb.AppendLine("虚拟桌面边界 (GetSystemMetrics): " + SystemInformation.VirtualScreen);
        }
        catch (Exception ex)
        {
            sb.AppendLine("异常: " + ex.GetType().Name + ": " + ex.Message);
        }
        finally
        {
            if (factoryPtr != IntPtr.Zero) Marshal.Release(factoryPtr);
        }
        return sb.ToString();
    }
}

public static class SelfChecker
{
    public static Color Pink = Color.FromArgb(233, 30, 99);

    public static int Dist(Color a, Color b)
    {
        return Math.Abs(a.R - b.R) + Math.Abs(a.G - b.G) + Math.Abs(a.B - b.B);
    }

    public static string Describe(Color c)
    {
        return "RGB(" + c.R + "," + c.G + "," + c.B + ")";
    }

    public static string Verdict(string pathName, bool controlOk, Color control, Color exempt, Color baseline)
    {
        if (!controlOk)
        {
            return "  [" + pathName + "] 抓屏不可用，无法判定。";
        }
        int dControl = Dist(control, Pink);
        int dExemptBase = Dist(exempt, baseline);
        int dExemptPink = Dist(exempt, Pink);
        int lum = (exempt.R + exempt.G + exempt.B) / 3;
        if (dControl > 150)
        {
            return "  [" + pathName + "] 对照阶段没抓到粉色(" + Describe(control) + ")，该路径抓屏异常，无法判定。";
        }
        if (dExemptBase <= 60)
        {
            return "  [" + pathName + "] 豁免生效：截图看到的是遮罩背后的真实桌面。";
        }
        if (dExemptPink <= 90)
        {
            return "  [" + pathName + "] 豁免失败：截图里能看到遮罩。";
        }
        if (lum < 30)
        {
            return "  [" + pathName + "] 豁免失败：遮罩区域在截图里变成了黑块。";
        }
        return "  [" + pathName + "] 无法判定（豁免阶段色 " + Describe(exempt) + "，基线 " + Describe(baseline) + "）。";
    }

    public static string Run(int blockMs)
    {
        StringBuilder sb = new StringBuilder();
        SCNative.SetProcessDPIAware();
        Screen screen = Screen.PrimaryScreen;
        int bw = 320, bh = 200;
        Rectangle r = new Rectangle(screen.WorkingArea.Right - bw - 30, screen.WorkingArea.Bottom - bh - 30, bw, bh);
        int cx = r.X + r.Width / 2;
        int cy = r.Y + r.Height / 2;

        sb.AppendLine("----------------------------------------");
        sb.AppendLine("第 1 阶段：基线（无测试窗）");
        Color gBase = GdiSampler.Sample(r);
        Color dBase = Color.Black;
        string dErr = "";
        bool dBaseOk = DxgiSampler.TrySample(cx, cy, out dBase, out dErr);
        sb.AppendLine("  GDI  基线 " + Describe(gBase));
        sb.AppendLine("  DXGI 基线 " + (dBaseOk ? Describe(dBase) : "不可用: " + dErr));
        Application.DoEvents();

        Color gControl = Color.Black, gExempt = Color.Black;
        Color dControl = Color.Black, dExempt = Color.Black;
        bool dControlOk = false, dExemptOk = false;

        sb.AppendLine("第 2 阶段：对照（粉色测试窗，无截图豁免）——请确认右下角出现粉色色块");
        using (TestWindow w = new TestWindow(r, false))
        {
            w.Show();
            Application.DoEvents();
            Thread.Sleep(blockMs);
            Application.DoEvents();
            gControl = GdiSampler.Sample(r);
            dControlOk = DxgiSampler.TrySample(cx, cy, out dControl, out dErr);
            sb.AppendLine("  GDI  对照 " + Describe(gControl));
            sb.AppendLine("  DXGI 对照 " + (dControlOk ? Describe(dControl) : "不可用: " + dErr));
        }
        Application.DoEvents();
        Thread.Sleep(300);

        sb.AppendLine("第 3 阶段：豁免（同一粉色测试窗 + WDA_EXCLUDEFROMCAPTURE）");
        using (TestWindow w = new TestWindow(r, true))
        {
            w.Show();
            Application.DoEvents();
            Thread.Sleep(blockMs);
            Application.DoEvents();
            gExempt = GdiSampler.Sample(r);
            dExemptOk = DxgiSampler.TrySample(cx, cy, out dExempt, out dErr);
            sb.AppendLine("  GDI  豁免 " + Describe(gExempt));
            sb.AppendLine("  DXGI 豁免 " + (dExemptOk ? Describe(dExempt) : "不可用: " + dErr));
        }

        sb.AppendLine("");
        sb.AppendLine("----------------------------------------");
        sb.AppendLine("判定（GDI = mss / PIL / pyautogui 类抓屏；DXGI = OBS / 部分截图工具）：");
        sb.AppendLine(Verdict("GDI", true, gControl, gExempt, gBase));
        sb.AppendLine(Verdict("DXGI", dControlOk, dControl, dExempt, dBase));
        sb.AppendLine("");
        sb.AppendLine("综合建议：");
        sb.AppendLine("  - 两条路径都是『豁免生效』 => 放心使用 privacy-screen.ps1（默认模式）。");
        sb.AppendLine("  - GDI 生效但 DXGI 失败 => AI 若用 mss/PIL/pyautogui 截图没问题；");
        sb.AppendLine("     若 AI 用 OBS 类 DXGI 抓屏，请改用 -ScreenOff 模式（物理灭屏+遮罩）。");
        sb.AppendLine("  - 任一『豁免失败』 => 该路径会把遮罩截进图里。");
        sb.AppendLine("----------------------------------------");
        return sb.ToString();
    }
}
'@

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition $src -ReferencedAssemblies 'System.Windows.Forms', 'System.Drawing'

if ($CompileOnly) {
    Write-Host 'OK: 代码编译通过。'
    exit 0
}

if ($DxgiDiag) {
    Write-Host ([DxgiSampler]::Diag())
    exit 0
}

Write-Host ''
Write-Host ([SelfChecker]::Run($BlockMs))
