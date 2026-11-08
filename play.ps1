$MusicDir = $PSScriptRoot

$SongArg = if ($args.Count -gt 0) { $args[0] } else { "" }

if (-not (Test-Path -LiteralPath $MusicDir)) {
    Write-Error "Directory not found: $MusicDir"
    exit
}

# Load WinMM
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.IO;
public class WinMM {
    [DllImport("winmm.dll")]
    public static extern int mciSendString(string command, StringBuilder buffer, int bufferSize, IntPtr hwndCallback);
}


// Controls the current process's Windows Core Audio session volume.
// The session is located by process ID so MCI playback remains unchanged.
public static class CoreAudioSessionVolume {
    private static readonly Guid MMDeviceEnumeratorClsid = new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E");
    private static readonly Guid AudioSessionManager2Iid = new Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F");

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDeviceEnumerator {
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, uint stateMask, out IntPtr devices);
        [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
        [PreserveSig] int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
        [PreserveSig] int RegisterEndpointNotificationCallback(IntPtr client);
        [PreserveSig] int UnregisterEndpointNotificationCallback(IntPtr client);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMMDevice {
        [PreserveSig] int Activate(ref Guid iid, uint clsctx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object instance);
        [PreserveSig] int OpenPropertyStore(uint access, out IntPtr properties);
        [PreserveSig] int GetId(out IntPtr id);
        [PreserveSig] int GetState(out uint state);
    }

    [ComImport, Guid("BFA971F1-4D5E-40BB-935E-967039BFBEE4"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioSessionManager {
        [PreserveSig] int GetAudioSessionControl(ref Guid sessionGuid, uint flags, out IAudioSessionControl sessionControl);
        [PreserveSig] int GetSimpleAudioVolume(ref Guid sessionGuid, uint flags, out ISimpleAudioVolume audioVolume);
    }

    [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioSessionManager2 : IAudioSessionManager {
        [PreserveSig] new int GetAudioSessionControl(ref Guid sessionGuid, uint flags, out IAudioSessionControl sessionControl);
        [PreserveSig] new int GetSimpleAudioVolume(ref Guid sessionGuid, uint flags, out ISimpleAudioVolume audioVolume);
        [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator sessionEnumerator);
        [PreserveSig] int RegisterSessionNotification(IntPtr notification);
        [PreserveSig] int UnregisterSessionNotification(IntPtr notification);
        [PreserveSig] int RegisterDuckNotification([MarshalAs(UnmanagedType.LPWStr)] string sessionId, IntPtr notification);
        [PreserveSig] int UnregisterDuckNotification(IntPtr notification);
    }

    [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioSessionEnumerator {
        [PreserveSig] int GetCount(out int count);
        [PreserveSig] int GetSession(int index, out IAudioSessionControl session);
    }

    [ComImport, Guid("F4B1A599-7266-4319-A8CA-E70ACB11E8CD"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioSessionControl {
        [PreserveSig] int GetState(out int state);
        [PreserveSig] int GetDisplayName(out IntPtr name);
        [PreserveSig] int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string name, ref Guid context);
        [PreserveSig] int GetIconPath(out IntPtr path);
        [PreserveSig] int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string path, ref Guid context);
        [PreserveSig] int GetGroupingParam(out Guid grouping);
        [PreserveSig] int SetGroupingParam(ref Guid grouping, ref Guid context);
        [PreserveSig] int RegisterAudioSessionNotification(IntPtr notification);
        [PreserveSig] int UnregisterAudioSessionNotification(IntPtr notification);
    }

    [ComImport, Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IAudioSessionControl2 : IAudioSessionControl {
        [PreserveSig] new int GetState(out int state);
        [PreserveSig] new int GetDisplayName(out IntPtr name);
        [PreserveSig] new int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string name, ref Guid context);
        [PreserveSig] new int GetIconPath(out IntPtr path);
        [PreserveSig] new int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string path, ref Guid context);
        [PreserveSig] new int GetGroupingParam(out Guid grouping);
        [PreserveSig] new int SetGroupingParam(ref Guid grouping, ref Guid context);
        [PreserveSig] new int RegisterAudioSessionNotification(IntPtr notification);
        [PreserveSig] new int UnregisterAudioSessionNotification(IntPtr notification);
        [PreserveSig] int GetSessionIdentifier(out IntPtr identifier);
        [PreserveSig] int GetSessionInstanceIdentifier(out IntPtr identifier);
        [PreserveSig] int GetProcessId(out uint processId);
        [PreserveSig] int IsSystemSoundsSession();
    }

    [ComImport, Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface ISimpleAudioVolume {
        [PreserveSig] int SetMasterVolume(float level, IntPtr eventContext);
        [PreserveSig] int GetMasterVolume(out float level);
        [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, IntPtr eventContext);
        [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
    }

    public static bool SetVolumeForProcess(int processId, float level, int retries, out string error) {
        error = null;
        if (level < 0.0f || level > 1.0f) {
            error = "Volume must be between 0.0 and 1.0.";
            return false;
        }

        for (int attempt = 0; attempt < Math.Max(1, retries); attempt++) {
            // MCI can create its audio session just after the play command.
            if (TrySetOnRole(processId, level, 0, out error)) return true; // eConsole
            string multimediaError;
            if (TrySetOnRole(processId, level, 1, out multimediaError)) return true; // eMultimedia
            if (!String.IsNullOrEmpty(multimediaError)) error = multimediaError;
            if (attempt + 1 < Math.Max(1, retries)) System.Threading.Thread.Sleep(100);
        }

        if (String.IsNullOrEmpty(error)) error = "No active Core Audio session was found for this player process.";
        return false;
    }

    private static bool TrySetOnRole(int processId, float level, int role, out string error) {
        error = null;
        IMMDeviceEnumerator deviceEnumerator = null;
        IMMDevice device = null;
        IAudioSessionManager2 manager = null;
        IAudioSessionEnumerator sessions = null;
        bool updated = false;

        try {
            Type enumeratorType = Type.GetTypeFromCLSID(MMDeviceEnumeratorClsid);
            deviceEnumerator = (IMMDeviceEnumerator)Activator.CreateInstance(enumeratorType);

            int hr = deviceEnumerator.GetDefaultAudioEndpoint(0, role, out device); // eRender
            if (hr < 0) Marshal.ThrowExceptionForHR(hr);

            object managerObject;
            Guid iid = AudioSessionManager2Iid;
            hr = device.Activate(ref iid, 23, IntPtr.Zero, out managerObject); // CLSCTX_ALL
            if (hr < 0) Marshal.ThrowExceptionForHR(hr);
            manager = (IAudioSessionManager2)managerObject;

            hr = manager.GetSessionEnumerator(out sessions);
            if (hr < 0) Marshal.ThrowExceptionForHR(hr);

            int count;
            hr = sessions.GetCount(out count);
            if (hr < 0) Marshal.ThrowExceptionForHR(hr);

            for (int i = 0; i < count; i++) {
                IAudioSessionControl session = null;
                try {
                    hr = sessions.GetSession(i, out session);
                    if (hr < 0 || session == null) continue;

                    IAudioSessionControl2 session2 = (IAudioSessionControl2)session;
                    uint ownerProcessId;
                    hr = session2.GetProcessId(out ownerProcessId);
                    if (hr < 0 || ownerProcessId != (uint)processId) continue;

                    ISimpleAudioVolume volume = (ISimpleAudioVolume)session2;
                    hr = volume.SetMasterVolume(level, IntPtr.Zero);
                    if (hr < 0) Marshal.ThrowExceptionForHR(hr);
                    updated = true;
                } catch (Exception ex) {
                    error = ex.Message;
                } finally {
                    if (session != null && Marshal.IsComObject(session)) {
                        try { Marshal.ReleaseComObject(session); } catch { }
                    }
                }
            }
        } catch (Exception ex) {
            error = ex.Message;
        } finally {
            if (sessions != null && Marshal.IsComObject(sessions)) {
                try { Marshal.ReleaseComObject(sessions); } catch { }
            }
            if (manager != null && Marshal.IsComObject(manager)) {
                try { Marshal.ReleaseComObject(manager); } catch { }
            }
            if (device != null && Marshal.IsComObject(device)) {
                try { Marshal.ReleaseComObject(device); } catch { }
            }
            if (deviceEnumerator != null && Marshal.IsComObject(deviceEnumerator)) {
                try { Marshal.ReleaseComObject(deviceEnumerator); } catch { }
            }
        }

        return updated;
    }
}

// Converts standard or extensible IEEE-float WAV audio to temporary PCM16 WAV.
// Returns false for non-float WAV files or unsupported/invalid float layouts.
public static class WavFloatConverter {
    private static readonly byte[] IeeeFloatSubFormat = new byte[] {
        0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00,
        0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71
    };

    public static bool TryConvert(string inputPath, long startOffset, string outputPath) {
        bool outputCreated = false;
        try {
            using (FileStream input = new FileStream(inputPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            using (BinaryReader reader = new BinaryReader(input)) {
                if (startOffset < 0 || startOffset + 12 > input.Length) return false;
                input.Position = startOffset;
                byte[] riff = reader.ReadBytes(12);
                if (riff.Length != 12 || Encoding.ASCII.GetString(riff, 0, 4) != "RIFF" ||
                    Encoding.ASCII.GetString(riff, 8, 4) != "WAVE") return false;

                long containerEnd = startOffset + 8L + BitConverter.ToUInt32(riff, 4);
                if (containerEnd > input.Length || containerEnd < startOffset + 12) return false;

                byte[] format = null;
                long dataOffset = -1;
                long dataSize = -1;
                long position = startOffset + 12;
                while (position + 8 <= containerEnd) {
                    input.Position = position;
                    byte[] chunkHeader = reader.ReadBytes(8);
                    if (chunkHeader.Length != 8) return false;
                    string chunkId = Encoding.ASCII.GetString(chunkHeader, 0, 4);
                    long chunkSize = BitConverter.ToUInt32(chunkHeader, 4);
                    long chunkData = position + 8;
                    long chunkEnd = chunkData + chunkSize;
                    long nextChunk = chunkEnd + (chunkSize & 1L);
                    if (chunkEnd > containerEnd || nextChunk > containerEnd) return false;

                    if (chunkId == "fmt " && format == null) {
                        if (chunkSize < 16) return false;
                        input.Position = chunkData;
                        format = reader.ReadBytes((int)Math.Min(chunkSize, 40L));
                        if (format.Length < 16) return false;
                    } else if (chunkId == "data" && dataOffset < 0) {
                        dataOffset = chunkData;
                        dataSize = chunkSize;
                    }
                    position = nextChunk;
                }

                if (position != containerEnd || format == null || dataOffset < 0 || dataSize <= 0) return false;

                ushort formatTag = BitConverter.ToUInt16(format, 0);
                int channels = BitConverter.ToUInt16(format, 2);
                uint sampleRate = BitConverter.ToUInt32(format, 4);
                uint byteRate = BitConverter.ToUInt32(format, 8);
                ushort blockAlign = BitConverter.ToUInt16(format, 12);
                ushort bitsPerSample = BitConverter.ToUInt16(format, 14);
                bool isFloat = formatTag == 3;

                if (formatTag == 0xFFFE) {
                    if (format.Length < 40 || BitConverter.ToUInt16(format, 16) < 22) return false;
                    if (BitConverter.ToUInt16(format, 18) != bitsPerSample) return false;
                    isFloat = true;
                    for (int i = 0; i < 16; i++) {
                        if (format[24 + i] != IeeeFloatSubFormat[i]) { isFloat = false; break; }
                    }
                }
                if (!isFloat) return false;
                if (channels < 1 || channels > 32 || sampleRate < 1 || sampleRate > 768000) return false;
                if (bitsPerSample != 32 && bitsPerSample != 64) return false;

                int bytesPerSample = bitsPerSample / 8;
                int expectedBlockAlign = channels * bytesPerSample;
                if (blockAlign != expectedBlockAlign || dataSize % blockAlign != 0 ||
                    byteRate != (long)sampleRate * blockAlign) return false;
                long outputDataSize = (dataSize / bytesPerSample) * 2L;
                long outputByteRate = (long)sampleRate * channels * 2L;
                int outputBlockAlign = channels * 2;
                if (outputDataSize > UInt32.MaxValue - 36L || outputByteRate > UInt32.MaxValue || outputBlockAlign > UInt16.MaxValue) return false;

                using (FileStream output = new FileStream(outputPath, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                using (BinaryWriter writer = new BinaryWriter(output)) {
                    outputCreated = true;
                    writer.Write(Encoding.ASCII.GetBytes("RIFF"));
                    writer.Write((uint)(36L + outputDataSize));
                    writer.Write(Encoding.ASCII.GetBytes("WAVE"));
                    writer.Write(Encoding.ASCII.GetBytes("fmt "));
                    writer.Write((uint)16);
                    writer.Write((ushort)1); // WAVE_FORMAT_PCM
                    writer.Write((ushort)channels);
                    writer.Write(sampleRate);
                    writer.Write((uint)outputByteRate);
                    writer.Write((ushort)outputBlockAlign);
                    writer.Write((ushort)16);
                    writer.Write(Encoding.ASCII.GetBytes("data"));
                    writer.Write((uint)outputDataSize);

                    input.Position = dataOffset;
                    byte[] buffer = new byte[65536 - (65536 % bytesPerSample)];
                    long remaining = dataSize;
                    while (remaining > 0) {
                        int wanted = (int)Math.Min(buffer.Length, remaining);
                        wanted -= wanted % bytesPerSample;
                        if (wanted <= 0) throw new IOException("Invalid IEEE-float WAV data length.");
                        int read = 0;
                        while (read < wanted) {
                            int count = input.Read(buffer, read, wanted - read);
                            if (count <= 0) throw new IOException("Unexpected end of IEEE-float WAV data.");
                            read += count;
                        }
                        for (int i = 0; i < read; i += bytesPerSample) {
                            double sample = bitsPerSample == 32
                                ? (double)BitConverter.ToSingle(buffer, i)
                                : BitConverter.ToDouble(buffer, i);
                            short pcmSample;
                            if (Double.IsNaN(sample) || Double.IsInfinity(sample)) pcmSample = 0;
                            else if (sample >= 1.0) pcmSample = Int16.MaxValue;
                            else if (sample <= -1.0) pcmSample = Int16.MinValue;
                            else pcmSample = (short)Math.Round(sample < 0 ? sample * 32768.0 : sample * 32767.0);
                            writer.Write(pcmSample);
                        }
                        remaining -= read;
                    }
                    writer.Flush();
                }
            }
            return true;
        } catch {
            if (outputCreated) {
                try { if (File.Exists(outputPath)) File.Delete(outputPath); } catch { }
            }
            return false;
        }
    }
}
"@

# Notification support
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Show-Notification($title, $text) {	
    $notify = New-Object System.Windows.Forms.NotifyIcon
    $notify.Icon = [System.Drawing.SystemIcons]::Information
    $notify.BalloonTipTitle = $title
    $notify.BalloonTipText = $text
    $notify.Visible = $true
    $notify.ShowBalloonTip(3000)
    Start-Sleep -Milliseconds 3500
    $notify.Dispose()
}

# Load songs
$global:Songs = Get-ChildItem -Path ([WildcardPattern]::Escape($MusicDir)) -Recurse -File -Include *.mp3, *.wav | Select-Object -ExpandProperty FullName

if (-not $global:Songs) {
    Write-Error "No audio files found"
    exit
}


$global:CliSongTarget = $null

if ($SongArg -ne "") {
    $results = $global:Songs | Where-Object {
        [System.IO.Path]::GetFileName($_) -like "*$SongArg*"
    }

    if (-not $results) {
        Write-Host "No songs found matching '$SongArg'." -ForegroundColor Red
        exit
    }

    $list = @($results)

    if ($list.Count -eq 1) {
        $global:CliSongTarget = $list[0]
    } else {
        Write-Host ""
        Write-Host "  Looking for '$SongArg' - did you mean one of these?" -ForegroundColor Yellow
        Write-Host ""
        for ($i = 0; $i -lt $list.Count; $i++) {
            Write-Host "  $($i + 1). $([System.IO.Path]::GetFileName($list[$i]))"
        }
        Write-Host ""
        Write-Host "Enter number (or 0 to cancel): " -NoNewline -ForegroundColor Yellow
        $choice = Read-Host

        if ($choice -eq "0" -or $choice -eq "") {
            Write-Host "  Cancelled." -ForegroundColor DarkGray
            exit
        }

        $choiceInt = 0
        if (-not [int]::TryParse($choice, [ref]$choiceInt) -or $choiceInt -lt 1 -or $choiceInt -gt $list.Count) {
            Write-Host "  Invalid selection." -ForegroundColor Red
            exit
        }

        $global:CliSongTarget = $list[$choiceInt - 1]
    }
}

# ---------------------------------------------------------------------------
# Audio leading-bytes handling (MP3 and WAV)
#
# MP3: locate three consecutive MPEG frames after ID3v2 tags or junk bytes.
# WAV: locate a structurally valid RIFF/WAVE container, validate its chunk
# boundaries and fmt/data chunks, and skip bytes before that container.
# IEEE-float WAV files are converted to temporary 16-bit PCM WAV files for MCI.
#
# The source file is never modified. Temporary files are used only for prefix
# removal or IEEE-float conversion. If detection/conversion is uncertain, the
# original file is used unchanged. RF64 and big-endian RIFX are not handled.
# ---------------------------------------------------------------------------

$global:TempAudioDir  = Join-Path ([System.IO.Path]::GetTempPath()) ("play-ps1-" + $PID)
$global:TempAudioFile = $null

$global:MpegBitrates = @{
    'V1L1'  = @(0,32,64,96,128,160,192,224,256,288,320,352,384,416,448)
    'V1L2'  = @(0,32,48,56,64,80,96,112,128,160,192,224,256,320,384)
    'V1L3'  = @(0,32,40,48,56,64,80,96,112,128,160,192,224,256,320)
    'V2L1'  = @(0,32,48,56,64,80,96,112,128,144,160,176,192,224,256)
    'V2L23' = @(0,8,16,24,32,40,48,56,64,80,96,112,128,144,160)
}
$global:MpegSampleRates = @{
    3 = @(44100, 48000, 32000)    # MPEG 1
    2 = @(22050, 24000, 16000)    # MPEG 2
    0 = @(11025, 12000, 8000)     # MPEG 2.5
}

# Returns MPEG frame information, or $null when the four bytes are not a
# supported MPEG audio header. Free-format frames are intentionally rejected
# because their frame length cannot be calculated from the header alone.
function Get-MpegFrameInfo {
    param([byte[]]$Buf, [int]$Pos)

    if ($Pos -lt 0 -or $Pos + 4 -gt $Buf.Length) { return $null }
    if ($Buf[$Pos] -ne 0xFF -or ($Buf[$Pos + 1] -band 0xE0) -ne 0xE0) { return $null }

    $verBits   = ($Buf[$Pos + 1] -shr 3) -band 3
    $layerBits = ($Buf[$Pos + 1] -shr 1) -band 3
    $brIdx     = ($Buf[$Pos + 2] -shr 4) -band 15
    $srIdx     = ($Buf[$Pos + 2] -shr 2) -band 3
    $pad       = ($Buf[$Pos + 2] -shr 1) -band 1

    # Reserved MPEG version, reserved layer, free/bad bitrate or reserved rate.
    if ($verBits -eq 1 -or $layerBits -eq 0 -or $brIdx -eq 0 -or $brIdx -eq 15 -or $srIdx -eq 3) {
        return $null
    }

    $isMpeg1 = ($verBits -eq 3)
    if ($layerBits -eq 3)     { $key = if ($isMpeg1) { 'V1L1' } else { 'V2L1' } }
    elseif ($layerBits -eq 2) { $key = if ($isMpeg1) { 'V1L2' } else { 'V2L23' } }
    else                      { $key = if ($isMpeg1) { 'V1L3' } else { 'V2L23' } }

    $bitrate = $global:MpegBitrates[$key][$brIdx] * 1000
    $sampleRate = $global:MpegSampleRates[$verBits][$srIdx]

    if ($layerBits -eq 3) {
        $frameLength = [int](([math]::Floor(12 * $bitrate / $sampleRate) + $pad) * 4)
    } else {
        $coefficient = if ($layerBits -eq 1 -and -not $isMpeg1) { 72 } else { 144 }
        $frameLength = [int]([math]::Floor($coefficient * $bitrate / $sampleRate) + $pad)
    }

    if ($frameLength -lt 4) { return $null }

    return [pscustomobject]@{
        Length     = $frameLength
        Version    = $verBits
        Layer      = $layerBits
        SampleRate = $sampleRate
    }
}

# Skip valid consecutive ID3v2 tags at the beginning of the file. The ID3v2.4
# tag size excludes its 10-byte header and, when present, its 10-byte footer.
function Get-Id3v2EndOffset {
    param([System.IO.FileStream]$Stream)

    $length = $Stream.Length
    $offset = 0L
    $header = New-Object byte[] 10

    while ($offset + 10 -le $length) {
        $Stream.Position = $offset
        if ($Stream.Read($header, 0, 10) -ne 10) { break }
        if ($header[0] -ne 0x49 -or $header[1] -ne 0x44 -or $header[2] -ne 0x33) { break }

        $major = [int]$header[3]
        $revision = [int]$header[4]
        $flags = [int]$header[5]

        if ($major -lt 2 -or $major -gt 4 -or $revision -eq 0xFF) { break }
        if (($major -lt 4 -and ($flags -band 0x1F) -ne 0) -or
            ($major -eq 4 -and ($flags -band 0x0F) -ne 0)) { break }

        # The four size bytes must be syncsafe (their high bits must be zero).
        if ((($header[6] -bor $header[7] -bor $header[8] -bor $header[9]) -band 0x80) -ne 0) { break }

        $tagSize = ([long]$header[6] -shl 21) -bor ([long]$header[7] -shl 14) -bor ([long]$header[8] -shl 7) -bor [long]$header[9]
        $hasFooter = ($major -eq 4 -and ($flags -band 0x10) -ne 0)
        $footerSize = if ($hasFooter) { 10L } else { 0L }
        $tagEnd = $offset + 10L + $tagSize + $footerSize

        if ($tagEnd -gt $length -or $tagEnd -le $offset) { break }

        if ($hasFooter) {
            $footer = New-Object byte[] 10
            $Stream.Position = $offset + 10L + $tagSize
            if ($Stream.Read($footer, 0, 10) -ne 10) { break }
            if ($footer[0] -ne 0x33 -or $footer[1] -ne 0x44 -or $footer[2] -ne 0x49) { break }
            $footerMatches = $true
            for ($j = 3; $j -lt 10; $j++) {
                if ($footer[$j] -ne $header[$j]) { $footerMatches = $false; break }
            }
            if (-not $footerMatches) { break }
        }

        $offset = $tagEnd
    }

    return $offset
}

# Returns the absolute offset of the first verified audio frame, or -1 when
# no sufficiently reliable frame sequence is found. Scans in small overlapping
# chunks, so even large prefixes are supported without reading the whole file.
function Get-AudioStartOffset {
    param([string]$File)

    $stream = [System.IO.File]::Open($File, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $fileLength = $stream.Length
        $startOffset = Get-Id3v2EndOffset -Stream $stream
        if ($startOffset -ge $fileLength) { return -1L }

        $chunkSize = 65536
        # Larger than the maximum supported MPEG frame length, with room for
        # the next two frame headers when a candidate is near a chunk boundary.
        $overlap = 4096
        $scanPosition = $startOffset

        while ($scanPosition -lt $fileLength) {
            $stream.Position = $scanPosition
            $toRead = [int][math]::Min($chunkSize, $fileLength - $scanPosition)
            $buffer = New-Object byte[] $toRead
            $bytesRead = 0
            while ($bytesRead -lt $toRead) {
                $count = $stream.Read($buffer, $bytesRead, $toRead - $bytesRead)
                if ($count -le 0) { break }
                $bytesRead += $count
            }

            if ($bytesRead -lt 4) { break }

            $isLastChunk = ($scanPosition + $bytesRead -ge $fileLength)
            $lastCandidate = if ($isLastChunk) { $bytesRead - 4 } else { $bytesRead - $overlap - 1 }

            for ($i = 0; $i -le $lastCandidate; $i++) {
                if ($buffer[$i] -ne 0xFF) { continue }

                $first = Get-MpegFrameInfo -Buf $buffer -Pos $i
                if ($null -eq $first) { continue }

                $secondPos = $i + $first.Length
                $second = Get-MpegFrameInfo -Buf $buffer -Pos $secondPos
                if ($null -eq $second) { continue }
                if ($second.Version -ne $first.Version -or $second.Layer -ne $first.Layer -or $second.SampleRate -ne $first.SampleRate) { continue }

                $thirdPos = $secondPos + $second.Length
                $third = Get-MpegFrameInfo -Buf $buffer -Pos $thirdPos
                if ($null -eq $third) { continue }
                if ($third.Version -ne $first.Version -or $third.Layer -ne $first.Layer -or $third.SampleRate -ne $first.SampleRate) { continue }

                return ($scanPosition + $i)
            }

            if ($isLastChunk) { break }
            $advance = $bytesRead - $overlap
            if ($advance -le 0) { break }
            $scanPosition += $advance
        }

        return -1L
    }
    finally {
        $stream.Dispose()
    }
}

# Validate a RIFF/WAVE container at a specific offset. The declared RIFF
# boundary must fit inside the file, and both fmt and non-empty data chunks
# must be present and remain inside that boundary. Unknown chunks are skipped
# using their declared size plus RIFF's required odd-byte padding.
function Test-WavContainerAtOffset {
    param(
        [System.IO.FileStream]$Stream,
        [long]$Offset
    )

    $fileLength = $Stream.Length
    if ($Offset -lt 0 -or $Offset + 12 -gt $fileLength) { return $false }

    $header = New-Object byte[] 12
    $Stream.Position = $Offset
    if ($Stream.Read($header, 0, 12) -ne 12) { return $false }
    if ([System.Text.Encoding]::ASCII.GetString($header, 0, 4) -cne 'RIFF' -or
        [System.Text.Encoding]::ASCII.GetString($header, 8, 4) -cne 'WAVE') { return $false }

    $riffSize = [long][BitConverter]::ToUInt32($header, 4)
    $containerEnd = $Offset + 8L + $riffSize
    if ($riffSize -lt 36 -or $containerEnd -gt $fileLength -or $containerEnd -le ($Offset + 12)) {
        return $false
    }

    $position = $Offset + 12L
    $hasFormat = $false
    $hasData = $false
    $chunkHeader = New-Object byte[] 8

    while ($position + 8L -le $containerEnd) {
        $Stream.Position = $position
        if ($Stream.Read($chunkHeader, 0, 8) -ne 8) { return $false }

        $chunkId = [System.Text.Encoding]::ASCII.GetString($chunkHeader, 0, 4)
        $chunkSize = [long][BitConverter]::ToUInt32($chunkHeader, 4)
        $chunkDataStart = $position + 8L
        $chunkEnd = $chunkDataStart + $chunkSize
        $nextChunk = $chunkEnd + ($chunkSize -band 1)
        if ($chunkEnd -gt $containerEnd -or $nextChunk -gt $containerEnd) { return $false }

        if ($chunkId -ceq 'fmt ') {
            if ($chunkSize -lt 16) { return $false }
            $fmt = New-Object byte[] 16
            $Stream.Position = $chunkDataStart
            if ($Stream.Read($fmt, 0, 16) -ne 16) { return $false }

            $formatTag = [int][BitConverter]::ToUInt16($fmt, 0)
            $channels = [int][BitConverter]::ToUInt16($fmt, 2)
            $sampleRate = [long][BitConverter]::ToUInt32($fmt, 4)
            $byteRate = [long][BitConverter]::ToUInt32($fmt, 8)
            $blockAlign = [int][BitConverter]::ToUInt16($fmt, 12)
            $bitsPerSample = [int][BitConverter]::ToUInt16($fmt, 14)

            if ($formatTag -eq 0 -or $channels -lt 1 -or $channels -gt 32 -or
                $sampleRate -lt 1 -or $sampleRate -gt 768000 -or
                $byteRate -lt 1 -or $blockAlign -lt 1 -or
                $bitsPerSample -lt 1 -or $bitsPerSample -gt 64) { return $false }

            # WAVE_FORMAT_EXTENSIBLE requires its 22-byte extension.
            if ($formatTag -eq 0xFFFE) {
                if ($chunkSize -lt 40) { return $false }
                $extensionSizeBytes = New-Object byte[] 2
                $Stream.Position = $chunkDataStart + 16
                if ($Stream.Read($extensionSizeBytes, 0, 2) -ne 2) { return $false }
                if ([BitConverter]::ToUInt16($extensionSizeBytes, 0) -lt 22) { return $false }
            }

            # PCM and IEEE float have predictable block alignment and byte rate.
            if ($formatTag -eq 1 -or $formatTag -eq 3) {
                $expectedAlign = [int]($channels * [math]::Ceiling($bitsPerSample / 8.0))
                if ($blockAlign -ne $expectedAlign -or $byteRate -ne ($sampleRate * $blockAlign)) {
                    return $false
                }
            }
            $hasFormat = $true
        }
        elseif ($chunkId -ceq 'data') {
            if ($chunkSize -le 0) { return $false }
            $hasData = $true
        }

        if ($nextChunk -le $position) { return $false }
        $position = $nextChunk
    }

    return ($position -eq $containerEnd -and $hasFormat -and $hasData)
}

# Find a valid RIFF/WAVE container anywhere in the file. The 64 KB chunk scan
# has a three-byte overlap so a RIFF signature crossing a chunk boundary is
# still checked. No fixed prefix-size limit is imposed.
function Get-WavStartOffset {
    param([string]$File)

    $stream = [System.IO.File]::Open($File, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $chunkSize = 65536
        $overlap = 3
        $scanPosition = 0L

        while ($scanPosition -lt $stream.Length) {
            $stream.Position = $scanPosition
            $toRead = [int][math]::Min($chunkSize, $stream.Length - $scanPosition)
            $buffer = New-Object byte[] $toRead
            $bytesRead = 0
            while ($bytesRead -lt $toRead) {
                $count = $stream.Read($buffer, $bytesRead, $toRead - $bytesRead)
                if ($count -le 0) { break }
                $bytesRead += $count
            }
            if ($bytesRead -lt 4) { break }

            $lastCandidate = $bytesRead - 4
            for ($i = 0; $i -le $lastCandidate; $i++) {
                if ($buffer[$i] -ne 0x52 -or $buffer[$i + 1] -ne 0x49 -or
                    $buffer[$i + 2] -ne 0x46 -or $buffer[$i + 3] -ne 0x46) { continue }

                $candidate = $scanPosition + $i
                if (Test-WavContainerAtOffset -Stream $stream -Offset $candidate) {
                    return $candidate
                }
            }

            if ($scanPosition + $bytesRead -ge $stream.Length) { break }
            $advance = $bytesRead - $overlap
            if ($advance -le 0) { break }
            $scanPosition += $advance
        }

        return -1L
    }
    finally {
        $stream.Dispose()
    }
}

# Returns the original path, or a temporary copy without the leading bytes.
# MP3 and WAV use separate format-specific detectors; uncertain files are
# passed to MCI unchanged.
function Get-PlayablePath {
    param([string]$File)

    $extension = [System.IO.Path]::GetExtension($File)
    if ($extension -ine '.mp3' -and $extension -ine '.wav') { return $File }

    $tmp = $null
    try {
        if ($extension -ieq '.mp3') {
            $start = Get-AudioStartOffset -File $File
        } else {
            $start = Get-WavStartOffset -File $File
        }
        if ($start -lt 0) { return $File }

        [void][System.IO.Directory]::CreateDirectory($global:TempAudioDir)

        # Convert standard and extensible IEEE-float WAV files to PCM16 for MCI.
        # The converter reads from the detected RIFF offset, so prefixed files
        # do not need an intermediate stripped copy.
        if ($extension -ieq '.wav') {
            $converted = Join-Path $global:TempAudioDir ([guid]::NewGuid().ToString('N') + '.wav')
            if ([WavFloatConverter]::TryConvert($File, $start, $converted)) {
                $global:TempAudioFile = $converted
                return $converted
            }
            if (Test-Path -LiteralPath $converted) {
                Remove-Item -LiteralPath $converted -Force -ErrorAction SilentlyContinue
            }
        }

        # If no conversion is needed, retain the existing leading-byte handling.
        if ($start -eq 0) { return $File }

        $tempExtension = if ($extension -ieq '.mp3') { '.mp3' } else { '.wav' }
        $tmp = Join-Path $global:TempAudioDir ([guid]::NewGuid().ToString('N') + $tempExtension)

        $inputStream = [System.IO.File]::Open($File, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $inputStream.Position = $start
            $outputStream = [System.IO.File]::Create($tmp)
            try {
                $inputStream.CopyTo($outputStream)
            }
            finally {
                $outputStream.Dispose()
            }
        }
        finally {
            $inputStream.Dispose()
        }

        $global:TempAudioFile = $tmp
        return $tmp
    }
    catch {
        if ($tmp -and (Test-Path -LiteralPath $tmp)) {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
        return $File
    }
}
function Remove-TempAudio {
    if ($global:TempAudioFile -and (Test-Path -LiteralPath $global:TempAudioFile)) {
        Remove-Item -LiteralPath $global:TempAudioFile -Force -ErrorAction SilentlyContinue
    }
    $global:TempAudioFile = $null
}

function Shuffle-Queue {
    $currentFile = if ($global:PreSearchFile) {
        $global:PreSearchFile                              
    } elseif ($global:Queue -and $global:Queue.Count -gt 0) {
        $global:Queue[$global:Index]
    } else { $null }

    $global:PreSearchFile = $null                        

    $global:Queue       = @($global:Songs | Sort-Object { Get-Random })
    $global:Index       = 0
    $global:CursorIndex = 0

    if ($currentFile) {
        $foundAt = [array]::IndexOf($global:Queue, $currentFile)
        $global:LastPlayedIndex = if ($foundAt -ge 0) { $foundAt } else { 0 }
    } else {
        $global:LastPlayedIndex = 0
    }
}

function Show-Queue {
    Write-Host "`n--- QUEUE ---"
    for ($i = 0; $i -lt $global:Queue.Count; $i++) {
        $name = [System.IO.Path]::GetFileName($global:Queue[$i])
        if ($i -eq $global:Index -and $i -eq $global:LastPlayedIndex) {
            Write-Host ">> * $name" -ForegroundColor Cyan
        } elseif ($i -eq $global:Index) {
            Write-Host ">>   $name" -ForegroundColor Green
        } elseif ($i -eq $global:LastPlayedIndex) {
            Write-Host "  *  $name" -ForegroundColor Yellow
        } else {
            Write-Host "     $name"
        }
    }
    $loopStatus   = if ($global:LoopMode)   { "ON" } else { "OFF" }
    $repeatStatus = if ($global:RepeatOne)  { "ON" } else { "OFF" }
    $searchStatus = if ($global:SearchMode) { " [SEARCH MODE]" } else { "" }
    Write-Host "   [Loop: $loopStatus]  [Repeat: $repeatStatus]  [Vol: $global:Volume%]$searchStatus" -ForegroundColor DarkCyan
    Write-Host "--------------"
    Write-Host "  Q = View Queue/Navigate" -ForegroundColor DarkGray
}

function Open-Navigator {
    $global:CursorIndex = $global:Index

    while ($true) {
        [console]::Clear()
        Write-Host "`n--- NAVIGATOR ---"
        for ($i = 0; $i -lt $global:Queue.Count; $i++) {
            $name = [System.IO.Path]::GetFileName($global:Queue[$i])
            if ($i -eq $global:Index -and $i -eq $global:CursorIndex) {
                Write-Host ">> * $name" -ForegroundColor Cyan
            } elseif ($i -eq $global:Index) {
                Write-Host ">>   $name" -ForegroundColor Green
            } elseif ($i -eq $global:CursorIndex) {
                Write-Host "  *  $name" -ForegroundColor Yellow
            } else {
                Write-Host "     $name"
            }
        }
        $loopStatus   = if ($global:LoopMode)   { "ON" } else { "OFF" }
        $repeatStatus = if ($global:RepeatOne)  { "ON" } else { "OFF" }
        $searchStatus = if ($global:SearchMode) { " [SEARCH MODE]" } else { "" }
        Write-Host "   [Loop: $loopStatus]  [Repeat: $repeatStatus]  [Vol: $global:Volume%]$searchStatus" -ForegroundColor DarkCyan
        Write-Host "--------------"
        Write-Host "  Up/Down = Navigate | Enter = Play | F = Search | P = Pause | Q = Close" -ForegroundColor DarkGray
        Write-Host ""

        $k = [console]::ReadKey($true).Key
        switch ($k) {
            "UpArrow" {
                if ($global:CursorIndex -gt 0) {
                    $global:CursorIndex--
                } else {
                    $global:CursorIndex = $global:Queue.Count - 1
                }
            }
            "DownArrow" {
                if ($global:CursorIndex -lt ($global:Queue.Count - 1)) {
                    $global:CursorIndex++
                } else {
                    $global:CursorIndex = 0
                }
            }
            "Enter" {
                $global:LastPlayedIndex = $global:Index
                Stop-Current
                $global:Index = $global:CursorIndex
                [console]::Clear()
                Play-Current
                return
            }
            "P" { Toggle-Pause }
            "F" {
                [console]::Clear()
                Write-Host "Search: " -NoNewline -ForegroundColor Yellow
                $query = Read-Host

                if (-not $query) { break }

                $results = $global:Songs | Where-Object {
                    [System.IO.Path]::GetFileName($_) -like "*$query*"
                }

                if (-not $results) {
                    Write-Host "  No match found for '$query'." -ForegroundColor Red
                    Start-Sleep -Milliseconds 800
                    break
                }

                $list = @($results)
                Write-Host ""
                for ($i = 0; $i -lt $list.Count; $i++) {
                    Write-Host "  $($i + 1). $([System.IO.Path]::GetFileName($list[$i]))"
                }
                Write-Host ""
                Write-Host "Enter number (append 'a' to add to queue only, 0 to cancel): " -NoNewline -ForegroundColor Yellow
                $choice = Read-Host

                if ($choice -eq "0" -or $choice -eq "") { break }

                $addOnly = $false
                if ($choice.Length -ge 2 -and $choice[-1] -eq 'A') {
                    $addOnly = $true
                    $choice = $choice.Substring(0, $choice.Length - 1)
                }

                $choiceInt = 0
                if (-not [int]::TryParse($choice, [ref]$choiceInt) -or $choiceInt -lt 1 -or $choiceInt -gt $list.Count) {
                    Write-Host "  Invalid selection." -ForegroundColor Red
                    Start-Sleep -Milliseconds 800
                    break
                }

                $chosen = $list[$choiceInt - 1]

                if ($addOnly) {
                    if ($global:Queue -contains $chosen) {
                        Write-Host "  Song already in queue." -ForegroundColor Yellow
                        Start-Sleep -Milliseconds 800
                        break
                    }
                    $global:Queue = $global:Queue + $chosen
                    Write-Host "  Added to queue." -ForegroundColor Green
                    Start-Sleep -Milliseconds 800
                    break
                }

                $newIndex = [array]::IndexOf($global:Queue, $chosen)
                if ($newIndex -lt 0) {
                    $global:Queue = $global:Queue + $chosen
                    $newIndex     = $global:Queue.Count - 1
                }

                $global:LastPlayedIndex = $global:Index
                Stop-Current
                $global:Index       = $newIndex
                $global:CursorIndex = $newIndex
                [console]::Clear()
                Play-Current
                return
            }
            "Q" {
                [console]::Clear()
                Write-Host "Now playing: $(Split-Path $global:Queue[$global:Index] -Leaf)" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Controls:"
                Write-Host "  N = Next       | B = Previous  | P = Pause/Play"
                Write-Host "  S = Shuffle    | Q = View Queue | QQ = Navigate | F = Search"
                Write-Host "  L = Toggle Loop (queue) | R = Toggle Repeat (current song)"
                Write-Host "  + = Volume Up  | - = Volume Down"
                Write-Host "  X = Exit"
                Write-Host ""
                return
            }
        }
    }
}

function Get-TrackDuration {
    $buf = New-Object System.Text.StringBuilder 128
    [WinMM]::mciSendString("status $global:Alias length", $buf, 128, [IntPtr]::Zero) | Out-Null
    return [int]$buf.ToString()
}

function Get-TrackPosition {
    $buf = New-Object System.Text.StringBuilder 128
    [WinMM]::mciSendString("status $global:Alias position", $buf, 128, [IntPtr]::Zero) | Out-Null
    return [int]$buf.ToString()
}

function Format-Time($ms) {
    $totalSec = [math]::Floor($ms / 1000)
    $min = [math]::Floor($totalSec / 60)
    $sec = $totalSec % 60
    return "{0}:{1:00}" -f $min, $sec
}

function Show-Progress {
    if (-not $global:Alias) { return }
    $pos = Get-TrackPosition
    $dur = Get-TrackDuration
    if ($dur -le 0) { return }
    $posStr = Format-Time $pos
    $durStr = Format-Time $dur
    $pct = [math]::Floor(($pos / $dur) * 30)
    $bar = ("[" + "#" * $pct + "-" * (30 - $pct) + "]")
    $state = if ($global:Paused) { "PAUSED" } else { "PLAYING" }
    Write-Host "`r  $state  $bar  $posStr / $durStr   " -NoNewline
}

function Set-Volume($vol, $waitForSession = $false) {
    $global:Volume = [math]::Max(0, [math]::Min(100, $vol))
    $level = [single]($global:Volume / 100.0)
    $retries = if ($waitForSession) { 15 } else { 1 }
    $errorMessage = $null

    $success = [CoreAudioSessionVolume]::SetVolumeForProcess(
        $PID, $level, $retries, [ref]$errorMessage
    )

    if (-not $success) {
        Write-Host "`r  Volume control unavailable: $errorMessage   " -ForegroundColor Red
        return
    }
	
	if (-not $waitForSession) {
		Write-Host "`r  Volume: $global:Volume%   " -NoNewline
	}
}

function Play-Current {
    # Close the previous track (if any) and delete its temp copy before opening the next one
    Stop-Current

    $file = $global:Queue[$global:Index]
    $global:Alias = "audio$([guid]::NewGuid().ToString('N'))"
    Write-Host "`nNow playing: $(Split-Path $file -Leaf)" -ForegroundColor Cyan
    Show-Notification "Now Playing" (Split-Path $file -Leaf)

    # Remove a verified leading MP3/WAV prefix when present.
    $playPath = Get-PlayablePath $file
    $mciType = if ([System.IO.Path]::GetExtension($file) -ieq '.wav') { 'waveaudio' } else { 'mpegvideo' }

    $rc = [WinMM]::mciSendString("open `"$playPath`" type $mciType alias $global:Alias", $null, 0, [IntPtr]::Zero)
    if ($rc -ne 0 -and $playPath -ne $file) {
        # The stripped copy would not open: fall back to the original file
        Remove-TempAudio
        $rc = [WinMM]::mciSendString("open `"$file`" type $mciType alias $global:Alias", $null, 0, [IntPtr]::Zero)
    }
    if ($rc -ne 0) {
        Write-Host "  Could not open this file (MCI error $rc)." -ForegroundColor Red
    }

    [WinMM]::mciSendString("play $global:Alias", $null, 0, [IntPtr]::Zero) | Out-Null
    $global:Paused = $false
    Set-Volume $global:Volume $true
}

function Stop-Current {
    if ($global:Alias) {
        [WinMM]::mciSendString("stop $global:Alias", $null, 0, [IntPtr]::Zero) | Out-Null
        [WinMM]::mciSendString("close $global:Alias", $null, 0, [IntPtr]::Zero) | Out-Null
    }
    Remove-TempAudio
}

function Toggle-Pause {
    if ($global:Paused) {
        [WinMM]::mciSendString("resume $global:Alias", $null, 0, [IntPtr]::Zero) | Out-Null
        $global:Paused = $false
    } else {
        [WinMM]::mciSendString("pause $global:Alias", $null, 0, [IntPtr]::Zero) | Out-Null
        $global:Paused = $true
    }
}

function Toggle-Loop {
    $global:LoopMode = -not $global:LoopMode
    $status = if ($global:LoopMode) { "ON" } else { "OFF" }
    Write-Host "`n  Loop mode: $status" -ForegroundColor DarkCyan
}

function Toggle-Repeat {
    $global:RepeatOne = -not $global:RepeatOne
    $status = if ($global:RepeatOne) { "ON" } else { "OFF" }
    Write-Host "`n  Repeat current song: $status" -ForegroundColor DarkCyan
}

function Next-Track {
    $global:LastPlayedIndex = $global:Index
    Stop-Current
    $global:Index++
    if ($global:Index -ge $global:Queue.Count) { $global:Index = 0 }
    Play-Current
}

function Prev-Track {
    $global:LastPlayedIndex = $global:Index
    Stop-Current
    $global:Index--
    if ($global:Index -lt 0) { $global:Index = $global:Queue.Count - 1 }
    Play-Current
}

function Search-And-Play {
    Write-Host ""
    $wasPlaying = -not $global:Paused
    if ($wasPlaying) {
        [WinMM]::mciSendString("pause $global:Alias", $null, 0, [IntPtr]::Zero) | Out-Null
        $global:Paused = $true
    }

    Write-Host "Search: " -NoNewline -ForegroundColor Yellow
    $query = Read-Host

    if (-not $query) {
        if ($wasPlaying) {
            [WinMM]::mciSendString("resume $global:Alias", $null, 0, [IntPtr]::Zero) | Out-Null
            $global:Paused = $false
        }
        Write-Host "  Search cancelled." -ForegroundColor DarkGray
        return
    }

    $results = $global:Songs | Where-Object {
        [System.IO.Path]::GetFileName($_) -like "*$query*"
    }

    if (-not $results) {
        if ($wasPlaying) {
            [WinMM]::mciSendString("resume $global:Alias", $null, 0, [IntPtr]::Zero) | Out-Null
            $global:Paused = $false
        }
        Write-Host "  No matches found for '$query'." -ForegroundColor Red
        return
    }

    $list = @($results)
    Write-Host ""
    for ($i = 0; $i -lt $list.Count; $i++) {
        Write-Host "  $($i + 1). $([System.IO.Path]::GetFileName($list[$i]))"
    }
    Write-Host ""
    Write-Host "Enter number (or 0 to cancel): " -NoNewline -ForegroundColor Yellow
    $choice = Read-Host

    if ($choice -eq "0" -or $choice -eq "") {
        if ($wasPlaying) {
            [WinMM]::mciSendString("resume $global:Alias", $null, 0, [IntPtr]::Zero) | Out-Null
            $global:Paused = $false
        }
        Write-Host "  Cancelled." -ForegroundColor DarkGray
        return
    }

    $choiceInt = 0
    if (-not [int]::TryParse($choice, [ref]$choiceInt) -or $choiceInt -lt 1 -or $choiceInt -gt $list.Count) {
        if ($wasPlaying) {
            [WinMM]::mciSendString("resume $global:Alias", $null, 0, [IntPtr]::Zero) | Out-Null
            $global:Paused = $false
        }
        Write-Host "  Invalid selection." -ForegroundColor Red
        return
    }

    $chosen = $list[$choiceInt - 1]
    $global:LastPlayedIndex = $global:Index
    Stop-Current

    $global:PreSearchQueue  = $global:Queue
    $global:PreSearchIndex  = $global:Index
	$global:PreSearchFile   = $chosen
    $global:SearchMode      = $true

    $global:Queue     = @($chosen)
    $global:Index     = 0
    $global:LoopMode  = $false
    $global:RepeatOne = $false

    Write-Host "  [Search mode: playing single song]" -ForegroundColor DarkYellow
    Play-Current
}

function Exit-SearchMode {
    $global:PreSearchFile   = $global:Queue[$global:Index]
    $global:Queue           = @($global:PreSearchQueue)
    $global:Index           = $global:PreSearchIndex
    $global:LoopMode        = $false
    $global:RepeatOne       = $false
    $global:SearchMode      = $false
}

function Start-EndOfQueueCountdown {
    $global:WaitingForLoop = $true

    if ($global:Queue.Count -eq 1) {
        $songName = [System.IO.Path]::GetFileName($global:Queue[0])
        Write-Host "`nFinished: $songName" -ForegroundColor DarkYellow
        Write-Host "Press L to replay this song, or exiting in..." -ForegroundColor Yellow
        Show-Notification "Song Finished" "Press L to replay, or player exits in 5 seconds."
    } else {
        Write-Host "`nQueue finished. Press L to loop, or exiting in..." -ForegroundColor Yellow
        Show-Notification "Queue Finished" "Press L to loop, or player exits in 5 seconds."
    }

    for ($i = 5; $i -ge 1; $i--) {
        Write-Host "$i..." -ForegroundColor Yellow -NoNewline
        for ($t = 0; $t -lt 4; $t++) {
            if ([console]::KeyAvailable) {
                $k = [console]::ReadKey($true).Key
                if ($k -eq "L") {
                    Write-Host ""
                    $global:LastPlayedIndex = $global:Index
                    $global:Index           = 0
                    $global:WaitingForLoop  = $false
                    if ($global:Queue.Count -eq 1) {
                        Write-Host "  Replaying song..." -ForegroundColor Green
                    } else {
                        Write-Host "  Looping queue from start!" -ForegroundColor Green
                    }
                    Play-Current
                    return
                }
                if ($k -eq "X") {
                    Write-Host ""
                    Stop-Current
                    $global:Running        = $false
                    $global:WaitingForLoop = $false
                    if ($global:SearchMode) { Exit-SearchMode }
                    return
                }
            }
            Start-Sleep -Milliseconds 250
        }
    }

    Write-Host ""
    Write-Host "Exiting." -ForegroundColor Red
    Stop-Current
    if ($global:SearchMode) { Exit-SearchMode }
    $global:Running        = $false
    $global:WaitingForLoop = $false
}

# Initialize
$global:LoopMode        = $false
$global:RepeatOne       = $false
$global:Paused          = $false
$global:Running         = $true
$global:WaitingForLoop  = $false
$global:Volume          = 100
$global:SearchMode      = $false
$global:PreSearchQueue  = $null
$global:CursorIndex     = 0
$global:LastPlayedIndex = 0
$global:QueueOpen       = $false
$global:PreSearchFile = $null

Shuffle-Queue

if ($global:CliSongTarget) {
    $global:PreSearchQueue = @($global:Queue)
    $foundAt = [array]::IndexOf($global:Queue, $global:CliSongTarget)   
    $global:SearchMode     = $true
    $global:Queue          = @($global:CliSongTarget)
    $global:Index          = 0
    $global:LoopMode       = $false
    $global:RepeatOne      = $false
    Write-Host "  [Search mode: playing single song]" -ForegroundColor DarkYellow
}

Show-Queue
Play-Current

Write-Host "Controls:"
Write-Host "  N = Next       | B = Previous  | P = Pause/Play"
Write-Host "  S = Shuffle    | Q = View Queue | QQ = Navigate | F = Search"
Write-Host "  L = Toggle Loop (queue) | R = Toggle Repeat (current song)"
Write-Host "  + = Volume Up  | - = Volume Down"
Write-Host "  X = Exit"
Write-Host "  (Loop and Repeat are OFF by default.)"
Write-Host ""

# Main loop (try/finally so the temp audio copy is removed even on Ctrl+C)
try {
while ($global:Running) {

    if (-not $global:WaitingForLoop) { Show-Progress }

    if (-not $global:WaitingForLoop -and [console]::KeyAvailable) {
        $key = [console]::ReadKey($true).Key

        if ($global:QueueOpen) {
            switch ($key) {
                "Q" {
                    $global:QueueOpen = $false
                    Open-Navigator
                }
                default {
                    $global:QueueOpen = $false
                    Write-Host ""
                    switch ($key) {
                        "N"        { Next-Track }
                        "B"        { Prev-Track }
                        "P"        { Toggle-Pause }
                        "S"        {



                            if ($global:SearchMode) { Exit-SearchMode }
                            Write-Host "`n  Shuffling..." -ForegroundColor Yellow
                            Stop-Current
                            Shuffle-Queue
                            Show-Queue
                            Play-Current
                        }
                        "L"        { Toggle-Loop }
                        "R"        { Toggle-Repeat }
                        "F"        { Search-And-Play }
                        "OemPlus"  { Set-Volume ($global:Volume + 10) }
                        "OemMinus" { Set-Volume ($global:Volume - 10) }
                        "X"        {
                            Write-Host ""
                            Stop-Current
                            $global:Running = $false
                        }
                        "UpArrow"   { }
                        "DownArrow" { }
                    }
                }
            }

        } else {
            switch ($key) {
                "N"        { Write-Host ""; Next-Track }
                "B"        { Write-Host ""; Prev-Track }
                "P"        { Toggle-Pause }
                "S"        {



                    if ($global:SearchMode) { Exit-SearchMode }
                    Write-Host "`n  Shuffling..." -ForegroundColor Yellow
                    Stop-Current
                    Shuffle-Queue
                    Show-Queue
                    Play-Current
                }
                "Q"        {
                    $global:QueueOpen   = $true
                    $global:CursorIndex = $global:Index
                    Write-Host ""
                    Show-Queue
                }
                "L"        { Toggle-Loop }
                "R"        { Toggle-Repeat }
                "F"        { Search-And-Play }
                "OemPlus"  { Set-Volume ($global:Volume + 10) }
                "OemMinus" { Set-Volume ($global:Volume - 10) }
                "X"        {
                    Write-Host ""
                    Stop-Current
                    $global:Running = $false
                }
                "UpArrow"   { }
                "DownArrow" { }
            }
        }
    }

    # Auto-next when song ends
    if (-not $global:WaitingForLoop -and $global:Alias) {
        $status = New-Object System.Text.StringBuilder 128
        [WinMM]::mciSendString("status $global:Alias mode", $status, 128, [IntPtr]::Zero) | Out-Null

        if ($status.ToString() -eq "stopped" -and -not $global:Paused) {
            if ($global:RepeatOne) {
                $global:LastPlayedIndex = $global:Index
                Stop-Current
                Play-Current
            } elseif ($global:Index + 1 -ge $global:Queue.Count) {
                if ($global:LoopMode) {
                    $global:LastPlayedIndex = $global:Index
                    Write-Host "`n  Restarting queue..." -ForegroundColor DarkCyan
                    $global:Index = 0
                    Play-Current
                } else {
                    Start-EndOfQueueCountdown
                }
            } else {
                $global:LastPlayedIndex = $global:Index
                $global:Index++
                Play-Current
            }
        }
    }

    Start-Sleep -Milliseconds 200
}
}
finally {
    Stop-Current
    if (Test-Path -LiteralPath $global:TempAudioDir) {
        Remove-Item -LiteralPath $global:TempAudioDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
