/*
 * ASK300Bridge.cs
 * P/Invoke bridge for the Fujifilm ASK-300 SDK (ASKAPI.dll / ASK300API.dll)
 *
 * The Fujifilm ASK SDK uses a C-style DLL interface.
 * Key functions exposed by ASKAPI.dll / ASK300API.dll:
 *
 *   MCP_Open()            - Initialize SDK, enumerate printers
 *   MCP_GetPrinterInfo()  - Get printer status, paper type, remaining count
 *   MCP_Print()           - Send a print job (image + size + qty + options)
 *   MCP_Close()           - Release SDK resources
 *
 * This bridge compiles into an in-memory assembly via Add-Type in PowerShell.
 */

using System;
using System.Runtime.InteropServices;
using System.IO;
using System.Drawing;
using System.Drawing.Imaging;

namespace GrandStores.ASK300
{
    // ─── ASK SDK Constants ────────────────────────────────────────────────────
    public static class AskConstants
    {
        // Printer IDs (from ASKDllDef.h)
        public const int PRINTER_ID_ASK300 = 101;

        // Paper Size IDs (from ASKSizeList.ini — ASK-300 specific)
        public const int SIZE_89x127   = 1;    // 3.5x5  (postcard)
        public const int SIZE_102x152  = 2;    // 4x6
        public const int SIZE_178x127  = 4;    // 7x5
        public const int SIZE_229x152  = 8;    // 9x6
        public const int SIZE_203x152  = 128;  // 8x6

        // Print modes (from PrintMode.ini)
        public const int PRINT_MODE_SPEED   = 0;  // Glossy speed priority
        public const int PRINT_MODE_QUALITY = 1;  // Glossy quality priority
        public const int PRINT_MODE_MATTE   = 5;  // Matte (ASK-300 exclusive)

        // Return codes
        public const int MCP_SUCCESS        = 0;
        public const int MCP_ERR_BUSY       = -1;
        public const int MCP_ERR_PRINTER    = -2;
        public const int MCP_ERR_PARAMETER  = -3;
        public const int MCP_ERR_NO_PAPER   = -4;
        public const int MCP_ERR_NOT_READY  = -5;

        // Printer status codes
        public const int STATUS_READY       = 0;
        public const int STATUS_PRINTING    = 1;
        public const int STATUS_PAPER_LOW   = 2;
        public const int STATUS_NO_PAPER    = 3;
        public const int STATUS_COVER_OPEN  = 4;
        public const int STATUS_ERROR       = 5;
    }

    // ─── Printer info structure returned by MCP_GetPrinterInfo ───────────────
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct MCP_PRINTER_INFO
    {
        public int    PrinterId;          // e.g. 101 = ASK-300
        public int    UsbNo;              // USB slot 0-7
        public int    Status;             // Printer status code
        public int    PaperRemainCount;   // Remaining prints (for current ribbon)
        public int    SizeId;             // Current loaded paper size
        public int    PrintMode;          // Current print mode
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
        public string Serial;             // Serial number string
    }

    // ─── Print job parameters ─────────────────────────────────────────────────
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct MCP_PRINT_PARAM
    {
        public int  UsbNo;         // Which printer (USB slot)
        public int  SizeId;        // Paper size to print
        public int  PrintMode;     // Speed / quality / matte
        public int  Copies;        // Number of copies (1-99)
        public int  ImageWidth;    // Source image width in pixels
        public int  ImageHeight;   // Source image height in pixels
        public int  BitsPerPixel;  // 24 (RGB) or 32 (RGBA)
        public IntPtr ImageData;   // Pointer to unmanaged RGB image bytes
    }

    // ─── P/Invoke declarations for ASKAPI.dll ────────────────────────────────
    public static class AskApi
    {
        private const string ASKAPI_DLL = "ASKAPI.dll";

        // Initialize the SDK. Pass path to the folder containing ASK DLLs.
        // Returns: number of printers found, or negative error code.
        [DllImport(ASKAPI_DLL, CallingConvention = CallingConvention.Cdecl,
                   EntryPoint = "MCP_Open", CharSet = CharSet.Ansi)]
        public static extern int Open([MarshalAs(UnmanagedType.LPStr)] string dllFolderPath);

        // Retrieve info for a specific printer by index (0-based).
        // Returns: MCP_SUCCESS or error code.
        [DllImport(ASKAPI_DLL, CallingConvention = CallingConvention.Cdecl,
                   EntryPoint = "MCP_GetPrinterInfo")]
        public static extern int GetPrinterInfo(int printerIndex, out MCP_PRINTER_INFO info);

        // Get total number of detected printers.
        [DllImport(ASKAPI_DLL, CallingConvention = CallingConvention.Cdecl,
                   EntryPoint = "MCP_GetPrinterCount")]
        public static extern int GetPrinterCount();

        // Send a print job.
        // Returns: MCP_SUCCESS or error code.
        [DllImport(ASKAPI_DLL, CallingConvention = CallingConvention.Cdecl,
                   EntryPoint = "MCP_Print")]
        public static extern int Print(ref MCP_PRINT_PARAM param);

        // Cancel the current print job for a printer.
        [DllImport(ASKAPI_DLL, CallingConvention = CallingConvention.Cdecl,
                   EntryPoint = "MCP_Cancel")]
        public static extern int Cancel(int usbNo);

        // Release SDK resources. Call on shutdown.
        [DllImport(ASKAPI_DLL, CallingConvention = CallingConvention.Cdecl,
                   EntryPoint = "MCP_Close")]
        public static extern int Close();

        // Get last error description (returns pointer to static ANSI string)
        [DllImport(ASKAPI_DLL, CallingConvention = CallingConvention.Cdecl,
                   EntryPoint = "MCP_GetLastErrorMessage")]
        public static extern IntPtr GetLastErrorMessagePtr();

        public static string GetLastError()
        {
            IntPtr p = GetLastErrorMessagePtr();
            return (p == IntPtr.Zero) ? "Unknown error" : Marshal.PtrToStringAnsi(p);
        }
    }

    // ─── High-level manager used by the PowerShell print server ──────────────
    public class Ask300Manager : IDisposable
    {
        private bool _initialized = false;
        private string _dllFolder;
        private static string _originalDir;

        public Ask300Manager(string dllFolder)
        {
            _dllFolder = Path.GetFullPath(dllFolder);
        }

        // Initialize SDK — must be called once at server startup
        public string Initialize()
        {
            if (_initialized) return "Already initialized";
            if (!Directory.Exists(_dllFolder))
                return "ERROR: ASK300 folder not found: " + _dllFolder;
            if (!File.Exists(Path.Combine(_dllFolder, "ASKAPI.dll")))
                return "ERROR: ASKAPI.dll not found in " + _dllFolder;

            // Windows DLL search path: must be in the current directory
            _originalDir = Directory.GetCurrentDirectory();
            Directory.SetCurrentDirectory(_dllFolder);

            int result = AskApi.Open(_dllFolder);
            if (result < 0)
                return "ERROR: MCP_Open failed: " + result + " - " + AskApi.GetLastError();

            _initialized = true;
            return "OK: SDK initialized. Printers detected: " + result;
        }

        // Get status of all detected printers as a JSON string
        public string GetPrinterStatus()
        {
            if (!_initialized) return "{\"error\":\"SDK not initialized\"}";
            int count = AskApi.GetPrinterCount();
            if (count <= 0) return "{\"error\":\"No printers found\",\"count\":0}";

            var sb = new System.Text.StringBuilder();
            sb.Append("{\"count\":" + count + ",\"printers\":[");
            for (int i = 0; i < count; i++)
            {
                MCP_PRINTER_INFO info;
                int r = AskApi.GetPrinterInfo(i, out info);
                if (r != AskConstants.MCP_SUCCESS)
                {
                    sb.Append("{\"index\":" + i + ",\"error\":\"GetPrinterInfo failed: " + r + "\"}");
                }
                else
                {
                    string statusText = StatusToText(info.Status);
                    sb.Append("{");
                    sb.Append("\"index\":" + i + ",");
                    sb.Append("\"printerId\":" + info.PrinterId + ",");
                    sb.Append("\"usbNo\":" + info.UsbNo + ",");
                    sb.Append("\"status\":" + info.Status + ",");
                    sb.Append("\"statusText\":\"" + statusText + "\",");
                    sb.Append("\"paperRemain\":" + info.PaperRemainCount + ",");
                    sb.Append("\"sizeId\":" + info.SizeId + ",");
                    sb.Append("\"printMode\":" + info.PrintMode + ",");
                    sb.Append("\"serial\":\"" + (info.Serial ?? "") + "\"");
                    sb.Append("}");
                }
                if (i < count - 1) sb.Append(",");
            }
            sb.Append("]}");
            return sb.ToString();
        }

        // Print a JPEG/PNG image from a byte array (base64-decoded)
        // Returns JSON with status
        public string PrintImage(byte[] imageBytes, int sizeId, int copies, int printMode, int usbNo)
        {
            if (!_initialized) return "{\"success\":false,\"error\":\"SDK not initialized\"}";

            // Decode image to raw RGB bitmap at the correct print resolution
            int targetW, targetH;
            if (!GetTargetDimensions(sizeId, out targetW, out targetH))
                return "{\"success\":false,\"error\":\"Unknown sizeId: " + sizeId + "\"}";

            // Load image and resize to print dimensions
            byte[] rgbData;
            try
            {
                rgbData = LoadAndResizeToRGB(imageBytes, targetW, targetH);
            }
            catch (Exception ex)
            {
                return "{\"success\":false,\"error\":\"Image decode failed: " + ex.Message.Replace("\"","'") + "\"}";
            }

            // Pin byte array in memory and send to SDK
            GCHandle handle = GCHandle.Alloc(rgbData, GCHandleType.Pinned);
            try
            {
                MCP_PRINT_PARAM param = new MCP_PRINT_PARAM
                {
                    UsbNo        = usbNo,
                    SizeId       = sizeId,
                    PrintMode    = printMode,
                    Copies       = copies,
                    ImageWidth   = targetW,
                    ImageHeight  = targetH,
                    BitsPerPixel = 24,
                    ImageData    = handle.AddrOfPinnedObject()
                };

                int result = AskApi.Print(ref param);
                if (result == AskConstants.MCP_SUCCESS)
                    return "{\"success\":true,\"message\":\"Print job sent\",\"copies\":" + copies + ",\"sizeId\":" + sizeId + "}";
                else
                    return "{\"success\":false,\"error\":\"MCP_Print failed: " + result + " - " + AskApi.GetLastError() + "\"}";
            }
            finally
            {
                handle.Free();
            }
        }

        // Resize image bytes to the exact pixel dimensions required by the printer
        private byte[] LoadAndResizeToRGB(byte[] imageBytes, int width, int height)
        {
            using (var ms = new MemoryStream(imageBytes))
            using (var srcImg = Image.FromStream(ms))
            using (var bmp = new Bitmap(width, height, PixelFormat.Format24bppRgb))
            using (var g = Graphics.FromImage(bmp))
            {
                // Auto-orient: if target is landscape and image is portrait (or vice-versa), rotate 90°
                if ((width > height && srcImg.Width < srcImg.Height) ||
                    (width < height && srcImg.Width > srcImg.Height))
                {
                    srcImg.RotateFlip(RotateFlipType.Rotate90FlipNone);
                }

                // Center crop-to-fill to avoid stretching
                double srcRatio = (double)srcImg.Width / srcImg.Height;
                double tgtRatio = (double)width / height;
                int drawW, drawH, drawX, drawY;

                if (srcRatio > tgtRatio)
                {
                    drawH = height;
                    drawW = (int)Math.Round(height * srcRatio);
                }
                else
                {
                    drawW = width;
                    drawH = (int)Math.Round(width / srcRatio);
                }
                drawX = (width - drawW) / 2;
                drawY = (height - drawH) / 2;

                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                g.CompositingQuality = System.Drawing.Drawing2D.CompositingQuality.HighQuality;
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.HighQuality;
                g.DrawImage(srcImg, drawX, drawY, drawW, drawH);

                // Extract raw BGR bytes (GDI bitmap is BGR internally, ASK SDK expects BGR)
                var rect = new Rectangle(0, 0, width, height);
                var data = bmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
                int stride = Math.Abs(data.Stride);
                byte[] raw = new byte[stride * height];
                Marshal.Copy(data.Scan0, raw, 0, raw.Length);
                bmp.UnlockBits(data);

                // If stride > width*3, trim padding
                if (stride == width * 3) return raw;
                byte[] trimmed = new byte[width * 3 * height];
                for (int row = 0; row < height; row++)
                    Array.Copy(raw, row * stride, trimmed, row * width * 3, width * 3);
                return trimmed;
            }
        }

        // Paper size pixels for ASK-300 (PrinterID=101) from ASKSizeList.ini
        private bool GetTargetDimensions(int sizeId, out int w, out int h)
        {
            // ASK-300 specific pixel dimensions
            switch (sizeId)
            {
                case 1:   w = 1568; h = 1076; return true;  // 89x127 (3.5x5)
                case 2:   w = 1864; h = 1228; return true;  // 102x152 (4x6) landscape
                case 4:   w = 1568; h = 2128; return true;  // 178x127 (7x5)
                case 8:   w = 1864; h = 2730; return true;  // 229x152 (9x6)
                case 128: w = 1864; h = 2422; return true;  // 203x152 (8x6)
                default:  w = 0;   h = 0;    return false;
            }
        }

        private string StatusToText(int status)
        {
            switch (status)
            {
                case AskConstants.STATUS_READY:      return "Ready";
                case AskConstants.STATUS_PRINTING:   return "Printing";
                case AskConstants.STATUS_PAPER_LOW:  return "Paper Low";
                case AskConstants.STATUS_NO_PAPER:   return "No Paper";
                case AskConstants.STATUS_COVER_OPEN: return "Cover Open";
                case AskConstants.STATUS_ERROR:      return "Error";
                default:                              return "Unknown";
            }
        }

        public void Dispose()
        {
            if (_initialized)
            {
                try { AskApi.Close(); } catch { }
                if (_originalDir != null)
                    try { Directory.SetCurrentDirectory(_originalDir); } catch { }
                _initialized = false;
            }
        }
    }

    // ─── Paper size lookup table (for UI / validation) ────────────────────────
    public static class Ask300PaperSizes
    {
        public static readonly System.Collections.Generic.Dictionary<int, string> Names
            = new System.Collections.Generic.Dictionary<int, string>
        {
            { 1,   "89x127mm (3.5x5\")" },
            { 2,   "102x152mm (4x6\")" },
            { 4,   "178x127mm (7x5\")" },
            { 8,   "229x152mm (9x6\")" },
            { 128, "203x152mm (8x6\")" }
        };

        public static string GetName(int sizeId)
        {
            string name;
            return Names.TryGetValue(sizeId, out name) ? name : "Unknown size";
        }
    }
}
