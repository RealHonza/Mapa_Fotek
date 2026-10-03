<# :
@echo off
title Mapa Fotek - Aktualizace dat (Autor: Jan BARTUNEK)
setlocal
cd /d "%~dp0"
set "PHOTO_DIR=%~dp0"
set "SCRIPT_FILE=%~f0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText($env:SCRIPT_FILE, [System.Text.Encoding]::UTF8))"
goto :eof
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"

# Verze programu – jediný zdroj, používá se v banneru i ve výstupním souboru
$scriptVersion = "2.18"
$scriptDate    = "01.10.2026"

$targetDir = $env:PHOTO_DIR
if (-not $targetDir -or -not (Test-Path -LiteralPath $targetDir)) {
    $targetDir = (Get-Location).Path
}

# ------------------------------------------------------------------
# Vystup vzdy do korene (vedle Mapa_Fotek.html), i kdyz skenujeme podslozku
# ------------------------------------------------------------------
$outputDir = $env:PHOTO_DIR
if (-not $outputDir) { $outputDir = $targetDir }
$scanRoot = $targetDir.TrimEnd('\')
$pickedSuffix = ""

function Write-ProgramBanner {
    $isEn = ($script:currentLang -eq "en")
    Write-Host "================================================================" -ForegroundColor Cyan
    if ($isEn) {
        Write-Host "               PHOTO MAP - DATA UPDATE                          " -ForegroundColor Cyan
    } else {
        Write-Host "               MAPA FOTEK - AKTUALIZACE DAT                     " -ForegroundColor Cyan
    }
    Write-Host "================================================================" -ForegroundColor Cyan
    if ($isEn) {
        Write-Host " Author      : Jan BARTUNEK" -ForegroundColor Yellow
        Write-Host " Updated     : $scriptDate (Version $scriptVersion)" -ForegroundColor Yellow
        Write-Host " Language    : CZ / " -NoNewline -ForegroundColor Yellow
        Write-Host "[ EN ]" -NoNewline -ForegroundColor Green
        Write-Host "    (stiskem 'C' pro cestinu)" -ForegroundColor Gray
    } else {
        Write-Host " Autor       : Jan BARTUNEK" -ForegroundColor Yellow
        Write-Host " Aktualizace : $scriptDate (Verze $scriptVersion)" -ForegroundColor Yellow
        Write-Host " Jazyk       : " -NoNewline -ForegroundColor Yellow
        Write-Host "[ CZ ]" -NoNewline -ForegroundColor Green
        Write-Host " / EN    (press 'E' for English)" -ForegroundColor Gray
    }
}

function Test-JunkDirName([string]$name) {
    # shodne se seznamem JunkDirNames v C# casti skriptu
    $junk = @('@eadir', '.@__thumb', '.thumbnails', '$recycle.bin', 'system volume information', '__macosx', '.trashes', '.trash')
    return ($junk -contains $name.ToLower())
}

function Select-TargetFolder([string]$rootDir) {
    # Interaktivni prohlizec slozek. Vraci zvolenou slozku, nebo $null (= konec bez akce).
    $isEn = ($script:currentLang -eq "en")
    $rootTrim = $rootDir.TrimEnd('\')
    $current = $rootTrim
    while ($true) {
        Clear-Host
        Write-ProgramBanner
        Write-Host ""
        Write-Host "================================================================" -ForegroundColor Cyan
        if ($isEn) {
            Write-Host "  SELECT TARGET FOLDER TO SCAN" -ForegroundColor Cyan
            Write-Host "  Current location: $current" -ForegroundColor White
        } else {
            Write-Host "  VYBER CILOVOU SLOZKU PRO SKEN" -ForegroundColor Cyan
            Write-Host "  Aktualni umisteni: $current" -ForegroundColor White
        }
        Write-Host "----------------------------------------------------------------" -ForegroundColor Cyan
        $dirs = @()
        try {
            $dirs = @(Get-ChildItem -LiteralPath $current -Directory -ErrorAction SilentlyContinue |
                      Where-Object { -not (Test-JunkDirName $_.Name) } |
                      Sort-Object -Property Name)
        } catch {}
        $perPage = 99
        $pageCount = [Math]::Max(1, [int][Math]::Ceiling($dirs.Count / [double]$perPage))
        $page = 1
        :input while ($true) {
            $start = ($page - 1) * $perPage
            $shown = [Math]::Min($perPage, $dirs.Count - $start)
            $chunk = @($dirs | Select-Object -Skip $start -First $shown)
            $rows = [int][Math]::Ceiling($chunk.Count / 3.0)
            for ($r = 0; $r -lt $rows; $r++) {
                $line = ""
                for ($c = 0; $c -lt 3; $c++) {
                    $idx = $start + ($c * $rows) + $r
                    if ($idx -lt $dirs.Count) {
                        $nm = $dirs[$idx].Name
                        if ($nm.Length -gt 28) { $nm = $nm.Substring(0, 25) + "..." }
                        $line += ("[{0,3}] {1,-32}" -f ($idx + 1), $nm)
                    }
                }
                Write-Host "  $line"
            }
            if ($dirs.Count -eq 0) {
                if ($isEn) { Write-Host "  (no subfolders)" -ForegroundColor Gray }
                else { Write-Host "  (zadne podslozky)" -ForegroundColor Gray }
            }
            Write-Host ""
            if ($isEn) {
                Write-Host "  [B] one level up    " -NoNewline -ForegroundColor White
                Write-Host "[F/Enter] PROCESS THIS FOLDER" -NoNewline -ForegroundColor Green
                Write-Host "    [K/Q] Back to main menu" -NoNewline -ForegroundColor Yellow
                if ($pageCount -gt 1) { Write-Host ("    [P] page $page/$pageCount") -NoNewline -ForegroundColor Cyan }
                Write-Host ""
                Write-Host "  [0] Exit program" -ForegroundColor Red
                $sel = Read-Host "  Choice"
            } else {
                Write-Host "  [B] o urovni vys    " -NoNewline -ForegroundColor White
                Write-Host "[F/Enter] ZPRACOVAT TUTO SLOZKU" -NoNewline -ForegroundColor Green
                Write-Host "    [K/Q] Zpet do hlavni nabidky" -NoNewline -ForegroundColor Yellow
                if ($pageCount -gt 1) { Write-Host ("    [P] stranka $page/$pageCount") -NoNewline -ForegroundColor Cyan }
                Write-Host ""
                Write-Host "  [0] Ukoncit program" -ForegroundColor Red
                $sel = Read-Host "  Volba"
            }
            if ($null -eq $sel -or $sel.Trim() -eq '') { return $current }
            $v = $sel.Trim().ToUpper()
            if ($v -eq '0') { [Environment]::Exit(0) }
            if ($v -eq 'F') { return $current }
            if ($v -eq 'K' -or $v -eq 'Q' -or $v -eq 'M') { return $null }
            if ($v -eq 'P' -and $pageCount -gt 1) { $page = ($page % $pageCount) + 1; continue input }
            if ($v -eq 'B') {
                if ($current -ne $rootTrim) {
                    $parent = Split-Path -Path $current -Parent
                    if ($parent -and $parent.Length -ge $rootTrim.Length) { $current = $parent }
                }
                break input
            }
            if ($v -match '^\d{1,3}$') {
                $n = [int]$v
                if ($n -ge 1 -and $n -le $dirs.Count) { $current = $dirs[$n - 1].FullName; break input }
            }
        }
    }
}



$csharpSource = @'
using System;
using System.IO;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Threading;
using System.Threading.Tasks;
using System.Globalization;
using System.Text.RegularExpressions;
using System.Windows.Media.Imaging;

public class PhotoRecordItem
{
    public string DateTakenStr { get; set; }
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public string RelativePath { get; set; }
    public string FileName { get; set; }
    public long FileSizeBytes { get; set; }
    public bool HasGps { get; set; }
    public string Status { get; set; }
}

public class ScanStats
{
    public long TotalFilesScanned;
    public long TotalBytesScanned;
    public long GpsBeforeDedup;
    public List<PhotoRecordItem> GpsRecords;
    public List<PhotoRecordItem> DupRecords;
    public List<PhotoRecordItem> NoGpsRecords;
    public List<PhotoRecordItem> AllRecords;
}

public class FolderStatItem
{
    public string FolderPathKey { get; set; }
    public string RelativePath { get; set; }
    public long FileCount { get; set; }
    public long TotalSizeBytes { get; set; }
    public string OldestFileStr { get; set; }
    public string NewestFileStr { get; set; }
}

public class FileItemForStat
{
    public string FileName { get; set; }
    public string DateTakenStr { get; set; }
    public long FileSizeBytes { get; set; }
}

public class UnifiedScanner
{
    // Nastaveni jazyka pro konzolovy vystup (Progres / Progress)
    public static bool IsEnglish = false;

    // Citace cteni souboru (pro souhrn chyb na konci)
    public static long ReadOkCount;
    public static long ReadFailCount;
    public static readonly ConcurrentDictionary<string, long> FailByExt = new ConcurrentDictionary<string, long>(StringComparer.OrdinalIgnoreCase);
    private static long _progressProcessed;

    // Rekoncilace poctu souboru oproti Pruzkunikovi Windows
    public static long SkippedOwnOutputs;
    public static long SkippedSidecars;
    public static long SkippedJunkFiles;
    public static long SkippedJunkDirs;
    public static long EnumErrors;

    private static double DecodeRational(ulong val)
    {
        ulong num = val & 0xFFFFFFFF;
        ulong den = (val >> 32) & 0xFFFFFFFF;
        if (den == 0) return 0;
        return (double)num / (double)den;
    }

    public static double? ConvertGpsToDecimal(ulong[] coords, string refStr)
    {
        if (coords == null || coords.Length < 3) return null;
        double deg = DecodeRational(coords[0]);
        double min = DecodeRational(coords[1]);
        double sec = DecodeRational(coords[2]);

        double dec = deg + (min / 60.0) + (sec / 3600.0);
        if (refStr != null && (refStr.StartsWith("S", StringComparison.OrdinalIgnoreCase) || refStr.StartsWith("W", StringComparison.OrdinalIgnoreCase)))
        {
            dec = -dec;
        }
        return dec;
    }

    private static readonly string[] DateFormats = new string[] {
        // Jednoznacne formaty (rok prvni / EXIF standard)
        "yyyy:MM:dd HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy/MM/dd HH:mm:ss",
        "yyyy-MM-ddTHH:mm:ss",       // ISO 8601 (XMP)
        "yyyy-MM-ddTHH:mm:ssK",
        "yyyy-MM-ddTHH:mm:sszzz",    // ISO s casovym pasmem
        "yyyy-MM-dd HH:mm:sszzz",
        // Ceska konvence – DEN PRVNI (pred mesicem-prvnim, aby nedochazelo k zamen!)
        "dd.MM.yyyy HH:mm:ss",
        "d.M.yyyy H:mm:ss",
        "dd.MM.yyyy HH:mm",
        "d.M.yyyy H:mm",
        "dd.MM.yyyy",
        "d.M.yyyy",
        // Rok prvni bez sekund
        "yyyy:MM:dd HH:mm",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd",
        "yyyy/MM/dd",
        // Kompaktni formaty (nazvy souboru)
        "yyyyMMdd_HHmmss",
        "yyyyMMdd-HHmmss",
        "yyyyMMdd'T'HHmmss",
        "yyyyMMdd",
        // Lomitkove formaty – nejprve den-prvni (ceska/europska konvence)
        "dd/MM/yyyy HH:mm:ss",
        "d/M/yyyy H:mm:ss",
        "dd/MM/yyyy HH:mm",
        "dd/MM/yyyy",
        // Americka konvence az jako posledni varianta z presnych formatu
        "MM/dd/yyyy HH:mm:ss",
        "M/d/yyyy H:mm:ss",
        "MM/dd/yyyy"
    };

    private static bool IsValidYear(DateTime dt)
    {
        return dt.Year >= 1900 && dt.Year <= 2100;
    }

    // Vyzkousi vice metadata dotazu a vrati prvni neprazdny vysledek
    private static object MetaQuery(BitmapMetadata md, params string[] queries)
    {
        foreach (string q in queries)
        {
            try { object o = md.GetQuery(q); if (o != null) return o; } catch {}
        }
        return null;
    }

    private static bool TryParseKnownFormats(string s, out DateTime dt)
    {
        dt = DateTime.MinValue;
        foreach (string fmt in DateFormats)
        {
            if (DateTime.TryParseExact(s, fmt, CultureInfo.InvariantCulture, DateTimeStyles.None, out dt) && IsValidYear(dt))
                return true;
        }
        return false;
    }

    public static string ParseDateTimeToFullStr(string dateTaken, string fileName, DateTime fileDate)
    {
        if (!string.IsNullOrWhiteSpace(dateTaken))
        {
            string s = dateTaken.Trim();
            DateTime dt;

            // 1) Presne zname formaty – pro nejednoznacne datumy ma prednost DEN PRVNI (ceska konvence),
            //    cimz se predchazi zamen mesice a dne pri prevodu na YYYYMMDD
            if (TryParseKnownFormats(s, out dt))
                return dt.ToString("yyyyMMdd_HHmmss");

            // 2) Obecny parse ceske kultury (d.M.yyyy = den prvni)
            if (DateTime.TryParse(s, new CultureInfo("cs-CZ"), DateTimeStyles.None, out dt) && IsValidYear(dt))
                return dt.ToString("yyyyMMdd_HHmmss");

            // 3) Posledni zachrana: invariantni kultura (mesic prvni – americka konvence)
            if (DateTime.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.None, out dt) && IsValidYear(dt))
                return dt.ToString("yyyyMMdd_HHmmss");
        }

        var matchWithTime = Regex.Match(fileName, @"(?<!\d)(19\d\d|20\d\d)(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])[_-]?([01]\d|2[0-3])([0-5]\d)([0-5]\d)(?!\d)");
        if (matchWithTime.Success)
        {
            return string.Format("{0}{1}{2}_{3}{4}{5}",
                matchWithTime.Groups[1].Value, matchWithTime.Groups[2].Value, matchWithTime.Groups[3].Value,
                matchWithTime.Groups[4].Value, matchWithTime.Groups[5].Value, matchWithTime.Groups[6].Value);
        }

        var matchDateOnly = Regex.Match(fileName, @"(?<!\d)(19\d\d|20\d\d)(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])(?!\d)");
        if (matchDateOnly.Success)
        {
            return matchDateOnly.Value + "_000000";
        }

        var matchDateHyphen = Regex.Match(fileName, @"(?<!\d)(19\d\d|20\d\d)[-_](0[1-9]|1[0-2])[-_](0[1-9]|[12]\d|3[01])(?!\d)");
        if (matchDateHyphen.Success)
        {
            return string.Format("{0}{1}{2}_000000", matchDateHyphen.Groups[1].Value, matchDateHyphen.Groups[2].Value, matchDateHyphen.Groups[3].Value);
        }

        var matchYearMonth = Regex.Match(fileName, @"\b(19\d\d|20\d\d)[-_]?(0[1-9]|1[0-2])\b");
        if (matchYearMonth.Success)
        {
            return string.Format("{0}{1}01_000000", matchYearMonth.Groups[1].Value, matchYearMonth.Groups[2].Value);
        }

        var matchYearOnly = Regex.Match(fileName, @"(?<!\d)(19\d\d|20\d\d)(?!\d)");
        if (matchYearOnly.Success)
        {
            return matchYearOnly.Groups[1].Value + "0101_000000";
        }

        return fileDate.ToString("yyyyMMdd_HHmmss");
    }

    public static PhotoRecordItem ProcessPhotoFile(string filePath, string rootBase)
    {
        var fi = new FileInfo(filePath);
        var rec = new PhotoRecordItem
        {
            FileName = fi.Name,
            FileSizeBytes = fi.Length,
            RelativePath = RelPath(filePath, rootBase),
            HasGps = false
        };

        string ext = fi.Extension.ToLower();
        if (ext == ".jpg" || ext == ".jpeg" || ext == ".heic" || ext == ".heif" || ext == ".avif"
            || ext == ".png" || ext == ".tif" || ext == ".tiff" || ext == ".bmp" || ext == ".gif" || ext == ".webp"
            || ext == ".dng" || ext == ".cr2" || ext == ".cr3" || ext == ".nef" || ext == ".arw"
            || ext == ".raf" || ext == ".orf" || ext == ".rw2" || ext == ".pef" || ext == ".srw")
        {
            try
            {
                using (var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                {
                    var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.DelayCreation, BitmapCacheOption.None);
                    if (decoder.Frames.Count > 0)
                    {
                        var frame = decoder.Frames[0];
                        var metadata = frame.Metadata as BitmapMetadata;
                        if (metadata != null)
                        {
                            // DATUM_CAS: cteme vzdy z EXIF, nezavisle na GPS
                            string exifDate = null;
                            try { exifDate = metadata.DateTaken; } catch {}
                            if (!string.IsNullOrWhiteSpace(exifDate))
                                rec.DateTakenStr = ParseDateTimeToFullStr(exifDate, fi.Name, fi.LastWriteTime);

                            object latObj = null, lonObj = null, latRefObj = null, lonRefObj = null;
                            // JPEG: /app1/ifd/gps/..., TIFF/DNG/RAW: /ifd/gps/... – vyzkouset obe varianty
                            latObj    = MetaQuery(metadata, "/app1/ifd/gps/subifd:{ulong=2}", "/app1/ifd/gps/{ushort=2}", "/ifd/gps/subifd:{ulong=2}", "/ifd/gps/{ushort=2}");
                            latRefObj = MetaQuery(metadata, "/app1/ifd/gps/subifd:{ulong=1}", "/app1/ifd/gps/{ushort=1}", "/ifd/gps/subifd:{ulong=1}", "/ifd/gps/{ushort=1}");
                            lonObj    = MetaQuery(metadata, "/app1/ifd/gps/subifd:{ulong=4}", "/app1/ifd/gps/{ushort=4}", "/ifd/gps/subifd:{ulong=4}", "/ifd/gps/{ushort=4}");
                            lonRefObj = MetaQuery(metadata, "/app1/ifd/gps/subifd:{ulong=3}", "/app1/ifd/gps/{ushort=3}", "/ifd/gps/subifd:{ulong=3}", "/ifd/gps/{ushort=3}");

                            ulong[] latArray = latObj as ulong[];
                            ulong[] lonArray = lonObj as ulong[];
                            string latRef = latRefObj as string;
                            string lonRef = lonRefObj as string;

                            if (latArray != null && lonArray != null)
                            {
                                double? lat = ConvertGpsToDecimal(latArray, latRef);
                                double? lon = ConvertGpsToDecimal(lonArray, lonRef);

                                if (lat.HasValue && lon.HasValue && (Math.Abs(lat.Value) > 0.0001 || Math.Abs(lon.Value) > 0.0001))
                                {
                                    rec.Latitude = Math.Round(lat.Value, 6);
                                    rec.Longitude = Math.Round(lon.Value, 6);
                                    rec.HasGps = true;
                                }
                            }
                        }
                    }
                }
                Interlocked.Increment(ref ReadOkCount);
            }
            catch
            {
                Interlocked.Increment(ref ReadFailCount);
                FailByExt.AddOrUpdate(ext, 1, (k, v) => v + 1);
            }
        }

        if (string.IsNullOrEmpty(rec.DateTakenStr))
        {
            rec.DateTakenStr = ParseDateTimeToFullStr(null, fi.Name, fi.LastWriteTime);
        }

        return rec;
    }

    public static PhotoRecordItem ProcessGoogleJson(string jsonPath, string rootBase)
    {
        try
        {
            string content = File.ReadAllText(jsonPath);
            if (!content.Contains("\"latitude\"") || !content.Contains("\"longitude\"")) return null;

            var matchTitle = Regex.Match(content, "\"title\"\\s*:\\s*\"([^\"]+)\"");
            string title = matchTitle.Success ? matchTitle.Groups[1].Value : Path.GetFileNameWithoutExtension(jsonPath);

            var matchLat = Regex.Match(content, "\"latitude\"\\s*:\\s*([-+]?[0-9]*\\.?[0-9]+)");
            var matchLon = Regex.Match(content, "\"longitude\"\\s*:\\s*([-+]?[0-9]*\\.?[0-9]+)");

            if (!matchLat.Success || !matchLon.Success) return null;

            double lat = double.Parse(matchLat.Groups[1].Value, CultureInfo.InvariantCulture);
            double lon = double.Parse(matchLon.Groups[1].Value, CultureInfo.InvariantCulture);

            if (Math.Abs(lat) < 0.0001 && Math.Abs(lon) < 0.0001) return null;
            if (Math.Abs(lat) > 90.0 || Math.Abs(lon) > 180.0) return null;

            string dateStr = "00000000_000000";
            var matchTime = Regex.Match(content, @"""photoTakenTime""\s*:\s*\{[^}]*""timestamp""\s*:\s*""?([0-9]{9,18})""?");
            if (!matchTime.Success)
            {
                matchTime = Regex.Match(content, @"""timestamp""\s*:\s*""?([0-9]{9,18})""?");
            }
            long epoch = 0;
            if (matchTime.Success && long.TryParse(matchTime.Groups[1].Value, out epoch))
            {
                // Google Takeout pouziva sekundy, milisekundy i mikrosekundy – normalizace na sekundy
                string rawTs = matchTime.Groups[1].Value;
                if (rawTs.Length >= 16) epoch /= 1000000;
                else if (rawTs.Length >= 13) epoch /= 1000;
                var dt = DateTimeOffset.FromUnixTimeSeconds(epoch).LocalDateTime;
                dateStr = dt.ToString("yyyyMMdd_HHmmss");
            }

            string photoPath = Path.Combine(Path.GetDirectoryName(jsonPath), title);
            long fSize = 0;
            string relPath = "";
            if (File.Exists(photoPath))
            {
                var fi = new FileInfo(photoPath);
                fSize = fi.Length;
                relPath = RelPath(photoPath, rootBase);
            }
            else
            {
                relPath = RelPath(jsonPath, rootBase);
            }

            return new PhotoRecordItem
            {
                FileName = title,
                DateTakenStr = dateStr,
                Latitude = Math.Round(lat, 6),
                Longitude = Math.Round(lon, 6),
                FileSizeBytes = fSize,
                RelativePath = relPath,
                HasGps = true
            };
        }
        catch { return null; }
    }

    public static double? ParseXmpCoordinate(string val)
    {
        if (string.IsNullOrWhiteSpace(val)) return null;
        val = val.Trim();
        bool isNegative = val.EndsWith("S", StringComparison.OrdinalIgnoreCase) || val.EndsWith("W", StringComparison.OrdinalIgnoreCase);
        val = Regex.Replace(val, @"[NSEWnsew]$", "").Trim();
        string[] parts = val.Split(new char[] { ',', ' ', ';' }, StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 1)
        {
            double deg;
            if (double.TryParse(parts[0].Replace(',', '.'), NumberStyles.Any, CultureInfo.InvariantCulture, out deg))
                return isNegative ? -deg : deg;
        }
        else if (parts.Length == 2)
        {
            double deg, min;
            if (double.TryParse(parts[0].Replace(',', '.'), NumberStyles.Any, CultureInfo.InvariantCulture, out deg) &&
                double.TryParse(parts[1].Replace(',', '.'), NumberStyles.Any, CultureInfo.InvariantCulture, out min))
            {
                double dec = deg + (min / 60.0);
                return isNegative ? -dec : dec;
            }
        }
        else if (parts.Length >= 3)
        {
            double deg, min, sec;
            if (double.TryParse(parts[0].Replace(',', '.'), NumberStyles.Any, CultureInfo.InvariantCulture, out deg) &&
                double.TryParse(parts[1].Replace(',', '.'), NumberStyles.Any, CultureInfo.InvariantCulture, out min) &&
                double.TryParse(parts[2].Replace(',', '.'), NumberStyles.Any, CultureInfo.InvariantCulture, out sec))
            {
                double dec = deg + (min / 60.0) + (sec / 3600.0);
                return isNegative ? -dec : dec;
            }
        }
        return null;
    }

    public static PhotoRecordItem ProcessXmpFile(string xmpPath, string rootBase)
    {
        try
        {
            string content = File.ReadAllText(xmpPath);
            if (!content.Contains("GPSLatitude") || !content.Contains("GPSLongitude")) return null;

            var matchLat = Regex.Match(content, @"GPSLatitude(?!Ref)(?:>|=""|=')([^<""']+)");
            var matchLon = Regex.Match(content, @"GPSLongitude(?!Ref)(?:>|=""|=')([^<""']+)");

            if (!matchLat.Success || !matchLon.Success) return null;

            double? lat = ParseXmpCoordinate(matchLat.Groups[1].Value);
            double? lon = ParseXmpCoordinate(matchLon.Groups[1].Value);

            if (!lat.HasValue || !lon.HasValue) return null;
            if (Math.Abs(lat.Value) < 0.0001 && Math.Abs(lon.Value) < 0.0001) return null;
            if (Math.Abs(lat.Value) > 90.0 || Math.Abs(lon.Value) > 180.0) return null;

            string dateStr = "00000000_000000";
            var matchDate = Regex.Match(content, @"(?:DateTimeOriginal|DateCreated|CreateDate)(?:>|=""|=')([^<""']+)");
            if (matchDate.Success)
            {
                dateStr = ParseDateTimeToFullStr(matchDate.Groups[1].Value, Path.GetFileName(xmpPath), File.GetLastWriteTime(xmpPath));
            }

            string dir = Path.GetDirectoryName(xmpPath);
            string baseNameWithoutXmp = Path.GetFileNameWithoutExtension(xmpPath);
            string title = baseNameWithoutXmp;
            string photoPath = "";
            long fSize = 0;

            string directPhoto = Path.Combine(dir, baseNameWithoutXmp);
            if (File.Exists(directPhoto) && !directPhoto.EndsWith(".xmp", StringComparison.OrdinalIgnoreCase))
            {
                photoPath = directPhoto;
                title = Path.GetFileName(directPhoto);
            }
            else
            {
                string[] possibleExts = new string[] { ".jpg", ".jpeg", ".dng", ".cr2", ".cr3", ".nef", ".arw", ".png", ".tif", ".heic", ".heif", ".avif",
                                                        ".raf", ".orf", ".rw2", ".pef", ".srw", ".bmp", ".gif", ".webp" };
                foreach (var ext in possibleExts)
                {
                    string testP = Path.Combine(dir, baseNameWithoutXmp + ext);
                    if (File.Exists(testP))
                    {
                        photoPath = testP;
                        title = Path.GetFileName(testP);
                        break;
                    }
                }
            }

            string relPath = "";
            if (!string.IsNullOrEmpty(photoPath) && File.Exists(photoPath))
            {
                var fi = new FileInfo(photoPath);
                fSize = fi.Length;
                relPath = RelPath(photoPath, rootBase);
            }
            else
            {
                relPath = RelPath(xmpPath, rootBase);
            }

            return new PhotoRecordItem
            {
                FileName = title,
                DateTakenStr = dateStr,
                Latitude = Math.Round(lat.Value, 6),
                Longitude = Math.Round(lon.Value, 6),
                FileSizeBytes = fSize,
                RelativePath = relPath,
                HasGps = true
            };
        }
        catch { return null; }
    }

    // ------------------------------------------------------------------
    // Filtr odpadnich systemovych souboru a slozek (NAS Synology, macOS, Windows)
    // ------------------------------------------------------------------
    private static readonly string[] JunkDirNames = new string[] {
        "@eadir", ".@__thumb", ".thumbnails", "$recycle.bin", "system volume information",
        "__macosx", ".trashes", ".trash"
    };

    // Povolene pripony relevantnich souboru (fotky, RAW, videa)
    private static readonly HashSet<string> ValidMediaExtensions = new HashSet<string>(StringComparer.OrdinalIgnoreCase) {
        // Fotky / Bezna obrazova data
        ".jpg", ".jpeg", ".heic", ".heif", ".avif", ".png", ".tif", ".tiff", ".bmp", ".gif", ".webp",
        // RAW formaty fotoaparatu
        ".dng", ".cr2", ".cr3", ".nef", ".arw", ".raf", ".orf", ".rw2", ".pef", ".srw",
        // Videa
        ".mp4", ".mov", ".m4v", ".avi", ".mkv", ".wmv", ".3gp", ".flv", ".mts", ".m2ts", ".mpg", ".mpeg"
    };

    private static readonly HashSet<string> VideoExtensions = new HashSet<string>(StringComparer.OrdinalIgnoreCase) {
        ".mp4", ".mov", ".m4v", ".avi", ".mkv", ".wmv", ".3gp", ".flv", ".mts", ".m2ts", ".mpg", ".mpeg"
    };

    public static bool IsValidMediaFile(string fileName)
    {
        string ext = Path.GetExtension(fileName);
        if (string.IsNullOrEmpty(ext)) return false;
        return ValidMediaExtensions.Contains(ext);
    }

    public static bool IsVideoFile(string fileName)
    {
        string ext = Path.GetExtension(fileName);
        if (string.IsNullOrEmpty(ext)) return false;
        return VideoExtensions.Contains(ext);
    }

    private static bool IsOwnOutputFile(string lowerName)
    {
        if (lowerName.StartsWith("mapa_fotek")) return true;
        if (lowerName.StartsWith("statistika_")) return true;
        if (lowerName.EndsWith(".bat") || lowerName.EndsWith(".ps1") || lowerName.EndsWith(".cmd")) return true;
        if (lowerName.EndsWith(".html") || lowerName.EndsWith(".htm")) return true;
        if (lowerName == "souradnice_fotek.txt" || lowerName == "statistika_fotky.csv") return true;
        return false;
    }

    private static bool IsJunkFileName(string lowerName)
    {
        if (lowerName.StartsWith("._")) return true; // AppleDouble – macOS resource fork, neni skutecny obrazek
        return lowerName == "thumbs.db" || lowerName == "desktop.ini" || lowerName == ".ds_store" || lowerName == ".picasa.ini" || lowerName.EndsWith(".tmp");
    }

    private static bool IsJunkDirName(string lowerName)
    {
        foreach (string j in JunkDirNames) { if (lowerName == j) return true; }
        return false;
    }

    // Podpora cest delsich nez 260 znaku – pruchod adresari pres prefix \\?\
    private static string PrefixLong(string p)
    {
        if (p.StartsWith(@"\\?\", StringComparison.Ordinal)) return p;
        if (p.StartsWith(@"\\", StringComparison.Ordinal)) return @"\\?\UNC\" + p.Substring(2);
        return @"\\?\" + p;
    }

    private static string StripLong(string p)
    {
        if (p.StartsWith(@"\\?\UNC\", StringComparison.Ordinal)) return @"\\" + p.Substring(8);
        if (p.StartsWith(@"\\?\", StringComparison.Ordinal)) return p.Substring(4);
        return p;
    }

    // Relativni cesta pro vystup (oreze \\?\ prefix i korenovou slozku)
    private static string RelPath(string fullPath, string rootBase)
    {
        string p = StripLong(fullPath);
        return p.Substring(rootBase.Length).TrimStart('\\', '/').Replace('\\', '/');
    }

    // Spolecna konstrukce zaznamu pro video/srt parsery
    private static PhotoRecordItem MakeRecord(string fileName, DateTime dateSource, double lat, double lon, long size, string rootBase, string actualPath)
    {
        return new PhotoRecordItem
        {
            FileName = fileName,
            DateTakenStr = ParseDateTimeToFullStr(null, fileName, dateSource),
            Latitude = lat,
            Longitude = lon,
            FileSizeBytes = size,
            RelativePath = RelPath(actualPath, rootBase),
            HasGps = true
        };
    }

    // ------------------------------------------------------------------
    // GNSS z MP4/MOV videi (QuickTime atom udta/©xyz – telefony, drony, kamery)
    // ------------------------------------------------------------------
    public static PhotoRecordItem ProcessVideoGps(string filePath, string rootBase)
    {
        try
        {
            var fi = new FileInfo(filePath);
            using (var fs = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            using (var br = new BinaryReader(fs))
            {
                long pos = 0;
                long len = fs.Length;
                while (pos + 8 <= len)
                {
                    fs.Seek(pos, SeekOrigin.Begin);
                    byte[] hdr = br.ReadBytes(8);
                    if (hdr.Length < 8) break;
                    long boxSize = ((long)hdr[0] << 24) | ((long)hdr[1] << 16) | ((long)hdr[2] << 8) | hdr[3];
                    long headerSize = 8;
                    if (boxSize == 1)
                    {
                        byte[] lrg = br.ReadBytes(8);
                        if (lrg.Length < 8) break;
                        boxSize = 0;
                        for (int i = 0; i < 8; i++) boxSize = (boxSize << 8) | lrg[i];
                        headerSize = 16;
                    }
                    else if (boxSize == 0) { boxSize = len - pos; }
                    if (boxSize < headerSize) break;

                    string type = System.Text.Encoding.ASCII.GetString(hdr, 4, 4);
                    if (type == "moov")
                    {
                        int readLen = (int)Math.Min(boxSize - headerSize, 64L * 1024 * 1024);
                        byte[] moov = br.ReadBytes(readLen);
                        PhotoRecordItem rec = ExtractQuickTimeGps(moov, fi, rootBase);
                        if (rec != null)
                        {
                            Interlocked.Increment(ref ReadOkCount);
                            return rec;
                        }
                        Interlocked.Increment(ref ReadOkCount);
                        return null;
                    }
                    pos += boxSize;
                }
            }
        }
        catch
        {
            Interlocked.Increment(ref ReadFailCount);
            FailByExt.AddOrUpdate(Path.GetExtension(filePath).ToLower(), 1, (k, v) => v + 1);
        }
        return null;
    }

    private static PhotoRecordItem ExtractQuickTimeGps(byte[] moov, FileInfo fi, string rootBase)
    {
        for (int i = 0; i <= moov.Length - 4; i++)
        {
            if (moov[i] == 0xA9 && moov[i + 1] == 0x78 && moov[i + 2] == 0x79 && moov[i + 3] == 0x7A)
            {
                int take = Math.Min(160, moov.Length - (i + 4));
                if (take <= 0) continue;
                string ascii = System.Text.Encoding.ASCII.GetString(moov, i + 4, take);
                // format zapisu: "+50.123456+014.234567/" (ISO 6709)
                var m = Regex.Match(ascii, @"([+-]\d{1,3}(?:\.\d+)?)([+-]\d{1,3}(?:\.\d+)?)");
                if (!m.Success) continue;

                double lat = double.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture);
                double lon = double.Parse(m.Groups[2].Value, CultureInfo.InvariantCulture);
                if (Math.Abs(lat) > 90.0 || Math.Abs(lon) > 180.0) continue;
                if (Math.Abs(lat) < 0.0001 && Math.Abs(lon) < 0.0001) continue;

                return MakeRecord(fi.Name, fi.LastWriteTime, Math.Round(lat, 6), Math.Round(lon, 6), fi.Length, rootBase, fi.FullName);
            }
        }
        return null;
    }

    // ------------------------------------------------------------------
    // GNSS z DJI .srt titulku – format GPS(lon,lat[,alt]) dle specifikace DJI
    // ------------------------------------------------------------------
    public static PhotoRecordItem ProcessSrtFile(string srtPath, string rootBase)
    {
        try
        {
            string content = File.ReadAllText(srtPath);
            double lat = 0, lon = 0;
            bool found = false;

            // 1) Novější DJI formát: [latitude: 50.123456] [longitude: 14.123456]
            var mLat = Regex.Match(content, @"(?:latitude|lat)\s*[:=]\s*([+-]?\d+(?:\.\d+)?)", RegexOptions.IgnoreCase);
            var mLon = Regex.Match(content, @"(?:longitude|lon|long)\s*[:=]\s*([+-]?\d+(?:\.\d+)?)", RegexOptions.IgnoreCase);
            if (mLat.Success && mLon.Success)
            {
                lat = double.Parse(mLat.Groups[1].Value, CultureInfo.InvariantCulture);
                lon = double.Parse(mLon.Groups[1].Value, CultureInfo.InvariantCulture);
                found = true;
            }

            // 2) Klasický DJI formát: GPS(lon, lat[, alt])
            if (!found)
            {
                var m = Regex.Match(content, @"GPS\s*[(:]\s*([+-]?\d+(?:\.\d+)?)\s*,\s*([+-]?\d+(?:\.\d+)?)");
                if (!m.Success) return null;

                double v1 = double.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture);
                double v2 = double.Parse(m.Groups[2].Value, CultureInfo.InvariantCulture);

                // DJI specifikace: GPS(delka, sirka, vyska) -> v1 = lon, v2 = lat
                lon = v1;
                lat = v2;

                // Pokud je druha hodnota mimo rozsah sirky (-90 az 90) a prvni je v nem, bylo to GPS(lat, lon)
                if (Math.Abs(lat) > 90.0 && Math.Abs(lon) <= 90.0)
                {
                    lat = v1;
                    lon = v2;
                }
            }

            if (Math.Abs(lat) > 90.0 || Math.Abs(lon) > 180.0) return null;
            if (Math.Abs(lat) < 0.0001 && Math.Abs(lon) < 0.0001) return null;

            string dir = Path.GetDirectoryName(srtPath);
            string baseName = Path.GetFileNameWithoutExtension(srtPath);
            string title = baseName;
            long fSize = 0;
            string actual = srtPath;

            // sparovat s videem stejneho jmena
            string[] vidExts = new string[] { ".mp4", ".mov", ".m4v", ".avi", ".mkv", ".wmv", ".3gp", ".flv", ".mts", ".m2ts", ".mpg", ".mpeg" };
            foreach (string vx in vidExts)
            {
                string cand = Path.Combine(dir, baseName + vx);
                if (File.Exists(cand))
                {
                    actual = cand;
                    title = baseName + vx;
                    fSize = new FileInfo(cand).Length;
                    break;
                }
            }

            return MakeRecord(title, File.GetLastWriteTime(actual), Math.Round(lat, 6), Math.Round(lon, 6), fSize, rootBase, actual);
        }
        catch { return null; }
    }

    public static ScanStats ScanAll(string rootBase)
    {
        var photoFiles = new List<string>();
        var jsonFiles = new List<string>();
        var xmpFiles = new List<string>();
        var videoFiles = new List<string>();
        var srtFiles = new List<string>();
        var q = new Queue<string>();
        q.Enqueue(PrefixLong(rootBase));

        long totalBytes = 0;

        ReadOkCount = 0;
        ReadFailCount = 0;
        FailByExt.Clear();
        SkippedOwnOutputs = 0;
        SkippedSidecars = 0;
        SkippedJunkFiles = 0;
        SkippedJunkDirs = 0;
        EnumErrors = 0;

        while (q.Count > 0)
        {
            string dir = q.Dequeue();
            try
            {
                var di = new DirectoryInfo(dir);
                foreach (var f in di.EnumerateFiles())
                {
                    string fullName = f.FullName; // s \\?\ prefixem kvuli dlouhym cestam – oreze az RelPath()
                    string n = f.Name.ToLower();
                    if (IsOwnOutputFile(n))
                    {
                        SkippedOwnOutputs++;
                        continue;
                    }
                    
                    if (IsJunkFileName(n))
                    {
                        SkippedJunkFiles++;
                        continue;
                    }

                    if (n.EndsWith(".json"))
                    {
                        jsonFiles.Add(fullName);
                        SkippedSidecars++;
                    }
                    else if (n.EndsWith(".xmp"))
                    {
                        xmpFiles.Add(fullName);
                        SkippedSidecars++;
                    }
                    else if (n.EndsWith(".srt"))
                    {
                        srtFiles.Add(fullName);
                        SkippedSidecars++;
                    }
                    else if (!IsValidMediaFile(f.Name))
                    {
                        SkippedJunkFiles++;
                        continue;
                    }
                    else if (IsVideoFile(f.Name))
                    {
                        videoFiles.Add(fullName);
                        totalBytes += f.Length;
                    }
                    else
                    {
                        photoFiles.Add(fullName);
                        totalBytes += f.Length;
                    }
                }
                foreach (var d in di.EnumerateDirectories())
                {
                    if (IsJunkDirName(d.Name.ToLower())) { SkippedJunkDirs++; }
                    else q.Enqueue(d.FullName);
                }
            }
            catch
            {
                EnumErrors++; // neprojitelná složka – přístup odmítnut, dlouhá cesta apod.
            }
        }

        var results = new ConcurrentDictionary<string, PhotoRecordItem>();
        var noGpsResults = new ConcurrentDictionary<string, PhotoRecordItem>(StringComparer.OrdinalIgnoreCase);
        var opts = new ParallelOptions { MaxDegreeOfParallelism = Environment.ProcessorCount };

        // Progres skenu (jen pri vetsich knihovnach)
        _progressProcessed = 0;
        long totalMedia = photoFiles.Count + videoFiles.Count;
        System.Threading.Timer progressTimer = null;
        if (totalMedia > 200)
        {
            progressTimer = new System.Threading.Timer(delegate {
                long p = Interlocked.Read(ref _progressProcessed);
                double pct = totalMedia > 0 ? (p * 100.0 / totalMedia) : 100.0;
                if (pct > 100.0) pct = 100.0;
                string label = IsEnglish ? "Progress" : "Progres";
                string unit = IsEnglish ? "files" : "souboru";
                try { Console.Write("\r   {0}: {1}/{2} {3} ({4:F1} %)    ", label, p, totalMedia, unit, pct); } catch {}
            }, null, 250, 250);
        }

        try
        {
            Parallel.ForEach(photoFiles, opts, f =>
            {
                var r = ProcessPhotoFile(f, rootBase);
                Interlocked.Increment(ref _progressProcessed);
                string key = r.RelativePath.ToLower();
                if (r.HasGps)
                {
                    results.TryAdd(key, r);
                }
                else
                {
                    // S: fotka bez GNSS – evidovat pro STAV=S (varianta A: kopie = 2x S, pocty sedi)
                    noGpsResults.TryAdd(key, r);
                }
            });

            if (jsonFiles.Count > 0)
            {
                Parallel.ForEach(jsonFiles, opts, j =>
                {
                    var r = ProcessGoogleJson(j, rootBase);
                    if (r != null && r.HasGps)
                    {
                        string key = r.RelativePath.ToLower();
                        results.TryAdd(key, r);
                    }
                });
            }

            if (xmpFiles.Count > 0)
            {
                Parallel.ForEach(xmpFiles, opts, x =>
                {
                    var r = ProcessXmpFile(x, rootBase);
                    if (r != null && r.HasGps)
                    {
                        string key = r.RelativePath.ToLower();
                        results.TryAdd(key, r);
                    }
                });
            }

            if (videoFiles.Count > 0)
            {
                Parallel.ForEach(videoFiles, opts, v =>
                {
                    var r = ProcessVideoGps(v, rootBase);
                    Interlocked.Increment(ref _progressProcessed);
                    if (r != null && r.HasGps)
                    {
                        results.TryAdd(r.RelativePath.ToLower(), r);
                    }
                    else
                    {
                        // S: video bez GNSS – vyrobit zaznam bez souradnic pro STAV=S
                        try
                        {
                            var fiV = new FileInfo(v);
                            string relV = RelPath(v, rootBase);
                            var recS = new PhotoRecordItem
                            {
                                FileName = fiV.Name,
                                FileSizeBytes = fiV.Length,
                                RelativePath = relV,
                                DateTakenStr = ParseDateTimeToFullStr(null, fiV.Name, fiV.LastWriteTime),
                                HasGps = false
                            };
                            noGpsResults.TryAdd(relV.ToLower(), recS);
                        }
                        catch {}
                    }
                });
            }

            if (srtFiles.Count > 0)
            {
                Parallel.ForEach(srtFiles, opts, s =>
                {
                    var r = ProcessSrtFile(s, rootBase);
                    if (r != null && r.HasGps)
                    {
                        results.TryAdd(r.RelativePath.ToLower(), r);
                    }
                });
            }
        }
        finally
        {
            if (progressTimer != null)
            {
                progressTimer.Dispose();
                if (totalMedia > 200) { try { Console.WriteLine(); } catch {} }
            }
        }

        var list = new List<PhotoRecordItem>(results.Values);

        // Seřadit dle DATUM_CAS (vzestupně), při shodě dle NAZEV_SOUBORU
        list.Sort((a, b) =>
        {
            int cmp = string.Compare(a.DateTakenStr, b.DateTakenStr, StringComparison.Ordinal);
            if (cmp != 0) return cmp;
            return string.Compare(a.FileName, b.FileName, StringComparison.OrdinalIgnoreCase);
        });

        long beforeDedup = list.Count;

        // Deduplikace ve dvou urovnich (jen zaznamy s GNSS):
        // 1) Identické záznamy (DATUM_CAS + NAZEV + LAT + LON) – prvni G, dalsi D
        // 2) Stejný soubor (název bez přípony) na stejném místě – sloučit, i když se datum liší
        //    (typicky EXIF vs. doplněk z Google JSON/XMP sidecar souboru) – ponechany G, vyrazeny D
        // Bez GNSS (S) se nededuplikuje – varianta A: kopie ve 2 slozkach = 2x S, aby sedely pocty.
        var exactSeen = new HashSet<string>();
        var byFilePos = new Dictionary<string, PhotoRecordItem>(StringComparer.Ordinal);
        var dupList = new List<PhotoRecordItem>();
        foreach (var r in list)
        {
            string exactKey = r.DateTakenStr + "|" + r.FileName.ToLowerInvariant() + "|"
                            + r.Latitude.ToString("F6", CultureInfo.InvariantCulture) + "|"
                            + r.Longitude.ToString("F6", CultureInfo.InvariantCulture);
            if (!exactSeen.Add(exactKey))
            {
                r.Status = "D";
                dupList.Add(r);
                continue;
            }

            string posKey = Path.GetFileNameWithoutExtension(r.FileName).ToLowerInvariant() + "|"
                          + r.Latitude.ToString("F4", CultureInfo.InvariantCulture) + "|"
                          + r.Longitude.ToString("F4", CultureInfo.InvariantCulture);

            PhotoRecordItem existing;
            if (byFilePos.TryGetValue(posKey, out existing))
            {
                bool exiZero = existing.DateTakenStr.StartsWith("00000000", StringComparison.Ordinal);
                bool curZero = r.DateTakenStr.StartsWith("00000000", StringComparison.Ordinal);
                if (exiZero && !curZero)
                {
                    // nahradit záznam bez data záznamem se skutečným datem – puvodni se stava duplicitou D
                    existing.Status = "D";
                    dupList.Add(existing);
                    byFilePos[posKey] = r;
                }
                else
                {
                    r.Status = "D";
                    dupList.Add(r);
                }
                continue;
            }
            byFilePos[posKey] = r;
        }

        var deduped = new List<PhotoRecordItem>(byFilePos.Values);
        foreach (var g in deduped) { g.Status = "G"; }
        foreach (var d in dupList) { if (string.IsNullOrEmpty(d.Status)) d.Status = "D"; }
        deduped.Sort((a, b) =>
        {
            int cmp = string.Compare(a.DateTakenStr, b.DateTakenStr, StringComparison.Ordinal);
            if (cmp != 0) return cmp;
            return string.Compare(a.FileName, b.FileName, StringComparison.OrdinalIgnoreCase);
        });
        dupList.Sort((a, b) =>
        {
            int cmp = string.Compare(a.DateTakenStr, b.DateTakenStr, StringComparison.Ordinal);
            if (cmp != 0) return cmp;
            return string.Compare(a.FileName, b.FileName, StringComparison.OrdinalIgnoreCase);
        });

        var noGpsList = new List<PhotoRecordItem>(noGpsResults.Values);
        foreach (var s in noGpsList) { s.Status = "S"; }
        noGpsList.Sort((a, b) =>
        {
            int cmp = string.Compare(a.DateTakenStr, b.DateTakenStr, StringComparison.Ordinal);
            if (cmp != 0) return cmp;
            return string.Compare(a.FileName, b.FileName, StringComparison.OrdinalIgnoreCase);
        });

        var allRecs = new List<PhotoRecordItem>(deduped.Count + dupList.Count + noGpsList.Count);
        allRecs.AddRange(deduped);
        allRecs.AddRange(dupList);
        allRecs.AddRange(noGpsList);
        allRecs.Sort((a, b) =>
        {
            int cmp = string.Compare(a.DateTakenStr, b.DateTakenStr, StringComparison.Ordinal);
            if (cmp != 0) return cmp;
            return string.Compare(a.FileName, b.FileName, StringComparison.OrdinalIgnoreCase);
        });

        return new ScanStats
        {
            TotalFilesScanned = photoFiles.Count + videoFiles.Count,
            TotalBytesScanned = totalBytes,
            GpsBeforeDedup = beforeDedup,
            GpsRecords = deduped,
            DupRecords = dupList,
            NoGpsRecords = noGpsList,
            AllRecords = allRecs
        };
    }

    // ------------------------------------------------------------------
    // Ziskani data souboru pro statistiku (EXIF -> regex v nazvu -> LastWriteTime)
    // ------------------------------------------------------------------
    public static string GetFileDateString(string filePath, string fileName, DateTime lastWriteTime)
    {
        string ext = Path.GetExtension(fileName).ToLowerInvariant();
        if (ext == ".jpg" || ext == ".jpeg" || ext == ".heic" || ext == ".heif" || ext == ".avif"
            || ext == ".png" || ext == ".tif" || ext == ".tiff" || ext == ".bmp" || ext == ".gif" || ext == ".webp"
            || ext == ".dng" || ext == ".cr2" || ext == ".cr3" || ext == ".nef" || ext == ".arw"
            || ext == ".raf" || ext == ".orf" || ext == ".rw2" || ext == ".pef" || ext == ".srw")
        {
            try
            {
                using (var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                {
                    var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.DelayCreation, BitmapCacheOption.None);
                    if (decoder.Frames.Count > 0)
                    {
                        var frame = decoder.Frames[0];
                        var metadata = frame.Metadata as BitmapMetadata;
                        if (metadata != null)
                        {
                            string dt = null;
                            try { dt = metadata.DateTaken; } catch {}
                            return ParseDateTimeToFullStr(dt, fileName, lastWriteTime);
                        }
                    }
                }
            }
            catch {}
        }
        return ParseDateTimeToFullStr(null, fileName, lastWriteTime);
    }

    // ------------------------------------------------------------------
    // Rekurzivni pruchod slozkami a vyhledani vsech slozek s relevantnimi soubory
    // Slozky jsou prochazeny abecedne na kazde urovni (i nekoncove slozky, pokud maji soubory)
    // ------------------------------------------------------------------
    private static void CollectFoldersWithFiles(string currentDir, List<string> dirsWithFiles)
    {
        try
        {
            var di = new DirectoryInfo(PrefixLong(currentDir));

            bool hasValidFiles = false;
            foreach (var f in di.EnumerateFiles())
            {
                string n = f.Name.ToLowerInvariant();
                if (IsOwnOutputFile(n))
                    continue;
                if (IsJunkFileName(n))
                    continue;
                if (n.EndsWith(".json") || n.EndsWith(".xmp") || n.EndsWith(".srt"))
                    continue;
                if (!IsValidMediaFile(f.Name))
                    continue;

                hasValidFiles = true;
                break;
            }

            if (hasValidFiles)
            {
                dirsWithFiles.Add(currentDir);
            }

            var subDirs = new List<string>();
            foreach (var d in di.EnumerateDirectories())
            {
                if (!IsJunkDirName(d.Name.ToLowerInvariant()))
                {
                    subDirs.Add(d.FullName);
                }
            }
            // Abecedni razeni podslozek pred dalsim sestupem
            subDirs.Sort((a, b) => string.Compare(StripLong(a), StripLong(b), StringComparison.OrdinalIgnoreCase));

            foreach (var sd in subDirs)
            {
                CollectFoldersWithFiles(sd, dirsWithFiles);
            }
        }
        catch
        {
            // Pristup odepren nebo chyba cteni
        }
    }

    // Citace pro progres statistiky (Volba c. 3)
    private static long _statProcessedFolders;
    private static long _statProcessedFiles;

    // ------------------------------------------------------------------
    // Generovani statistiky pro vsechny slozky se soubory (Volba c. 3)
    // ------------------------------------------------------------------
    public static List<FolderStatItem> GenerateFolderStatistics(string rootBase)
    {
        string cleanRoot = StripLong(rootBase).TrimEnd('\\', '/');
        var allDirs = new List<string>();
        CollectFoldersWithFiles(cleanRoot, allDirs);

        long totalFolders = allDirs.Count;
        _statProcessedFolders = 0;
        _statProcessedFiles = 0;

        System.Threading.Timer progressTimer = null;
        if (totalFolders > 0)
        {
            progressTimer = new System.Threading.Timer(delegate {
                long fld = Interlocked.Read(ref _statProcessedFolders);
                long fil = Interlocked.Read(ref _statProcessedFiles);
                double pct = totalFolders > 0 ? (fld * 100.0 / totalFolders) : 100.0;
                string label = IsEnglish ? "Progress" : "Progres";
                string unitFld = IsEnglish ? "folders" : "slozek";
                string unitFil = IsEnglish ? "files" : "souboru";
                try { Console.Write("\r   {0}: {1}/{2} {3} ({4:F1} %) – {5:N0} {6}    ", label, fld, totalFolders, unitFld, pct, fil, unitFil); } catch {}
            }, null, 150, 150);
        }

        var resultsArray = new FolderStatItem[allDirs.Count];
        var opts = new ParallelOptions { MaxDegreeOfParallelism = Environment.ProcessorCount };

        try
        {
            Parallel.For(0, allDirs.Count, opts, i =>
            {
                string dir = allDirs[i];
                try
                {
                    var di = new DirectoryInfo(PrefixLong(dir));
                    var files = new List<FileItemForStat>();
                    long dirBytes = 0;

                    foreach (var f in di.EnumerateFiles())
                    {
                        string fullName = f.FullName;
                        string n = f.Name.ToLowerInvariant();
                        if (IsOwnOutputFile(n))
                            continue;
                        if (IsJunkFileName(n))
                            continue;
                        if (n.EndsWith(".json") || n.EndsWith(".xmp") || n.EndsWith(".srt"))
                            continue;
                        if (!IsValidMediaFile(f.Name))
                            continue;

                        long sz = f.Length;
                        dirBytes += sz;

                        string dtStr = GetFileDateString(fullName, f.Name, f.LastWriteTime);
                        files.Add(new FileItemForStat
                        {
                            FileName = f.Name,
                            DateTakenStr = dtStr,
                            FileSizeBytes = sz
                        });
                        Interlocked.Increment(ref _statProcessedFiles);
                    }

                    // Relativni cesta vuci korenu skenu
                    string strippedDir = StripLong(dir);
                    string rel = "";
                    if (strippedDir.Length > cleanRoot.Length)
                    {
                        rel = strippedDir.Substring(cleanRoot.Length).TrimStart('\\', '/');
                    }
                    else
                    {
                        rel = Path.GetFileName(cleanRoot);
                    }

                    // 1. sloupec: cesta teto slozky - lomitka nahrazena podtrzitky
                    string key = rel.Replace('\\', '_').Replace('/', '_');
                    if (string.IsNullOrEmpty(key)) key = Path.GetFileName(cleanRoot);

                    string oldestStr = "-";
                    string newestStr = "-";

                    if (files.Count > 0)
                    {
                        files.Sort((a, b) =>
                        {
                            int cmp = string.Compare(a.DateTakenStr, b.DateTakenStr, StringComparison.Ordinal);
                            if (cmp != 0) return cmp;
                            return string.Compare(a.FileName, b.FileName, StringComparison.OrdinalIgnoreCase);
                        });

                        var oldest = files[0];
                        var newest = files[files.Count - 1];

                        oldestStr = oldest.DateTakenStr;
                        newestStr = newest.DateTakenStr;
                    }

                    resultsArray[i] = new FolderStatItem
                    {
                        FolderPathKey = key,
                        RelativePath = rel,
                        FileCount = files.Count,
                        TotalSizeBytes = dirBytes,
                        OldestFileStr = oldestStr,
                        NewestFileStr = newestStr
                    };
                }
                catch {}
                finally
                {
                    Interlocked.Increment(ref _statProcessedFolders);
                }
            });
        }
        finally
        {
            if (progressTimer != null)
            {
                progressTimer.Dispose();
                try {
                    long fld = Interlocked.Read(ref _statProcessedFolders);
                    long fil = Interlocked.Read(ref _statProcessedFiles);
                    string label = IsEnglish ? "Progress" : "Progres";
                    string unitFld = IsEnglish ? "folders" : "slozek";
                    string unitFil = IsEnglish ? "files" : "souboru";
                    Console.WriteLine("\r   {0}: {1}/{2} {3} (100,0 %) – {4:N0} {5}    ", label, fld, totalFolders, unitFld, fil, unitFil);
                } catch {}
            }
        }

        var result = new List<FolderStatItem>();
        for (int i = 0; i < resultsArray.Length; i++)
        {
            if (resultsArray[i] != null) result.Add(resultsArray[i]);
        }

        return result;
    }
}
'@

Add-Type -TypeDefinition $csharpSource -ReferencedAssemblies "PresentationCore", "WindowsBase", "System.Xaml", "System.Xml"

function Format-FileSize([long]$bytes) {
    if ($bytes -ge 1073741824) { return ("{0:N2} GB" -f ($bytes / 1073741824)) }
    if ($bytes -ge 1048576) { return ("{0:N2} MB" -f ($bytes / 1048576)) }
    if ($bytes -ge 1024) { return ("{0:N2} KB" -f ($bytes / 1024)) }
    return ("{0} B" -f $bytes)
}

$script:currentLang = "cs"
$isFirstRun = $true
:mainLoop while ($true) {
    $isEn = ($script:currentLang -eq "en")
    # Reset targetDir pro kazdy pruchod nabidkou
    $targetDir = $scanRoot + '\'
    $pickedSuffix = ""

    Clear-Host
    Write-ProgramBanner
    Write-Host ""
    if ($isEn) {
        if ($isFirstRun) {
            Write-Host " [1] Generate photo data (scan entire archive)  (Enter or auto in 3 s)" -ForegroundColor Green
        } else {
            Write-Host " [1] Generate photo data (scan entire archive)" -ForegroundColor Green
        }
        Write-Host " [2] Generate photo data (select specific subfolder)" -ForegroundColor Green
        Write-Host " [3] Generate photo archive statistics" -ForegroundColor Green
        Write-Host ""
        Write-Host " [I] Program information and guide" -ForegroundColor Cyan
        Write-Host ""
        Write-Host " [0] Exit program" -ForegroundColor Red
    } else {
        if ($isFirstRun) {
            Write-Host " [1] Generovat data fotek (spustit sken celeho archivu)  (Enter nebo automaticky za 3 s)" -ForegroundColor Green
        } else {
            Write-Host " [1] Generovat data fotek (spustit sken celeho archivu)" -ForegroundColor Green
        }
        Write-Host " [2] Generovat data fotek (vybrat konkretni podslozku)" -ForegroundColor Green
        Write-Host " [3] Generovat statistiku archivu fotek" -ForegroundColor Green
        Write-Host ""
        Write-Host " [I] Informace o programu a navod" -ForegroundColor Cyan
        Write-Host ""
        Write-Host " [0] Ukoncit program" -ForegroundColor Red
    }
    Write-Host ""

    $menuChoice = $null
    if ($env:MF_MENU) {
        $menuChoice = $env:MF_MENU.ToUpper()
        $env:MF_MENU = $null
    } elseif ($isFirstRun) {
        # První spuštění: 3 s timeout, pak auto-1
        $deadline = [DateTime]::Now.AddSeconds(3)
        while ([DateTime]::Now -lt $deadline) {
            $pressed = $null
            try { if ([Console]::KeyAvailable) { $pressed = [Console]::ReadKey($true).KeyChar } } catch { }
            if ($pressed -eq '1' -or $pressed -eq [char]13 -or $pressed -eq [char]10) { $menuChoice = '1'; break }
            if ($pressed -eq '2') { $menuChoice = '2'; break }
            if ($pressed -eq '3') { $menuChoice = '3'; break }
            if ($pressed -eq 'i' -or $pressed -eq 'I') { $menuChoice = 'I'; break }
            if ($pressed -eq 'c' -or $pressed -eq 'C') { $script:currentLang = 'cs'; $isFirstRun = $false; continue mainLoop }
            if ($pressed -eq 'e' -or $pressed -eq 'E') { $script:currentLang = 'en'; $isFirstRun = $false; continue mainLoop }
            if ($pressed -eq '0') { $menuChoice = '0'; break }
            Start-Sleep -Milliseconds 100
        }
        if ($null -eq $menuChoice) { $menuChoice = '1' }
    } else {
        # Další spuštění: čekat neomezeně na jednu klávesu (bez Enteru)
        $pressed = $null
        while ($null -eq $menuChoice) {
            try {
                if ([Console]::KeyAvailable) { $pressed = [Console]::ReadKey($true).KeyChar }
            } catch {
                $sel = Read-Host
                if ($sel) { $pressed = $sel.Trim()[0] } else { $pressed = [char]13 }
            }
            if ($pressed -eq '1' -or $pressed -eq [char]13 -or $pressed -eq [char]10) { $menuChoice = '1' }
            elseif ($pressed -eq '2') { $menuChoice = '2' }
            elseif ($pressed -eq '3') { $menuChoice = '3' }
            elseif ($pressed -eq 'i' -or $pressed -eq 'I') { $menuChoice = 'I' }
            elseif ($pressed -eq 'c' -or $pressed -eq 'C') { $script:currentLang = 'cs'; continue mainLoop }
            elseif ($pressed -eq 'e' -or $pressed -eq 'E') { $script:currentLang = 'en'; continue mainLoop }
            elseif ($pressed -eq '0') { $menuChoice = '0' }
            else { $pressed = $null; Start-Sleep -Milliseconds 100 }
        }
    }
    $isFirstRun = $false

    if ($menuChoice -eq '0') {
        [Environment]::Exit(0)
    }

    if ($menuChoice -eq 'I') {
        Clear-Host
        Write-ProgramBanner
        Write-Host ""
        Write-Host "================================================================" -ForegroundColor Cyan
        if ($isEn) {
            Write-Host "               PROGRAM INFORMATION AND GUIDE                    " -ForegroundColor Cyan
            Write-Host "================================================================" -ForegroundColor Cyan
            Write-Host ""
            Write-Host " ABOUT THE PROGRAM:" -ForegroundColor Yellow
            Write-Host "  This tool provides fast, parallel processing of photo and video archives."
            Write-Host "  It processes ALL media files, reads geographical coordinates (GNSS) and marks"
            Write-Host "  each record with STATUS: G=unique with GNSS (map), S=without GNSS, D=GNSS duplicate."
            Write-Host "  It generates data files for the interactive map application '" -NoNewline
            Write-Host "Mapa_Fotek.html" -ForegroundColor Cyan -NoNewline
            Write-Host "'."
            Write-Host "  It also allows generating comprehensive archive statistics to CSV format."
            Write-Host ""
            Write-Host " OPTIONS DESCRIPTION:" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  [1] Generate photo data (scan entire archive)" -ForegroundColor Green
            Write-Host "      - Scans the complete photo & video archive across all subfolders."
            Write-Host "      - Reads GNSS from EXIF metadata, QuickTime videos (MP4/MOV),"
            Write-Host "        Google Photos JSON, Adobe XMP, and DJI SRT drone subtitle files."
            Write-Host "      - Deduplicates matching GNSS records (first G, rest D) and sorts all chronologically."
            Write-Host "      - Contains ALL files: G=unique with GNSS (map), S=without GNSS, D=GNSS duplicates."
            Write-Host "      - Output file  : " -NoNewline; Write-Host "Mapa_Fotek_data_YYYYMMDD.txt" -ForegroundColor Cyan
            Write-Host "      - Output format: JavaScript data file (window.MAPA_FOTEK_DATA)"
            Write-Host "        Columns (semicolon-separated): DATE_TIME; NAME; LAT; LON; BYTES; PATH; STATUS"
            Write-Host "        Directly loaded and visualized by '" -NoNewline
            Write-Host "Mapa_Fotek.html" -ForegroundColor Cyan -NoNewline
            Write-Host "'."
            Write-Host ""
            Write-Host "  [2] Generate photo data (select specific subfolder)" -ForegroundColor Green
            Write-Host "      - Opens an interactive folder browser to pick a specific subfolder."
            Write-Host "      - Processes only the selected folder and creates a dedicated data file."
            Write-Host "      - Output file  : " -NoNewline; Write-Host "Mapa_Fotek_data_YYYYMMDD_FolderName.txt" -ForegroundColor Cyan
            Write-Host "      - Output format: Identical to option [1], intended for partial views."
            Write-Host ""
            Write-Host "  [3] Generate photo archive statistics" -ForegroundColor Green
            Write-Host "      - Analyzes the structure of all media folders in the archive."
            Write-Host "      - Calculates file counts, total size in bytes/GB, and finds oldest"
            Write-Host "        and newest files for each folder and globally (TOTAL row)."
            Write-Host "      - Output file  : " -NoNewline; Write-Host "Mapa_Fotek_statistika_YYYYMMDD.csv" -ForegroundColor Cyan
            Write-Host "      - Output format: Tabular CSV file (UTF-8 with BOM for Excel)"
            Write-Host "        Table 1: Detailed statistics for all individual subfolders"
            Write-Host "        Table 2: Aggregated summary of 1st-level main folders"
            Write-Host ""
            Write-Host " SUPPORTED FORMATS:" -ForegroundColor Yellow
            Write-Host "  - Photos : JPG, JPEG, HEIC, HEIF, AVIF, PNG, TIF, TIFF, BMP, GIF, WEBP"
            Write-Host "  - RAW    : DNG, CR2, CR3, NEF, ARW, RAF, ORF, RW2, PEF, SRW"
            Write-Host "  - Videos : MP4, MOV, M4V, AVI, MKV, WMV, 3GP, FLV, MTS, M2TS, MPG, MPEG"
            Write-Host "  - Meta   : JSON (Google Photos), XMP (Adobe), SRT (DJI drone)"
            Write-Host "  - Junk   : Thumbs.db, .picasa.ini, .tmp, .thm, scripts are excluded"
            Write-Host ""
            Write-Host "================================================================" -ForegroundColor Cyan
            Write-Host "  [K/Q] Back to main menu    " -NoNewline -ForegroundColor Yellow
            Write-Host "[0] Exit program" -ForegroundColor Red
            Write-Host "================================================================" -ForegroundColor Cyan
        } else {
            Write-Host "               INFORMACE O PROGRAMU A NAVOD                     " -ForegroundColor Cyan
            Write-Host "================================================================" -ForegroundColor Cyan
            Write-Host ""
            Write-Host " O PROGRAMU:" -ForegroundColor Yellow
            Write-Host "  Tento nastroj slouzi k rychlemu paralelnimu zpracovani archivu fotek"
            Write-Host "  a videi. Zpracuje VSECHNY soubory, nacte zemepisne souradnice (GNSS) a kazdy"
            Write-Host "  zaznam oznaci STAVEM: G=unikat s GNSS (mapa), S=bez GNSS, D=duplicita s GNSS."
            Write-Host "  Generuje datove podklady pro interaktivni mapovou aplikaci '" -NoNewline
            Write-Host "Mapa_Fotek.html" -ForegroundColor Cyan -NoNewline
            Write-Host "'."
            Write-Host "  Zaroven umoznuje detailni statisticky prehled archivu do formatu CSV."
            Write-Host ""
            Write-Host " POPIS JEDNOTLIVYCH MOZNOSTI:" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  [1] Generovat data fotek (spustit sken celeho archivu)" -ForegroundColor Green
            Write-Host "      - Projde kompletni archiv fotek a videi ve vsech podslozkach."
            Write-Host "      - Nacte GNSS z EXIF metadat fotek, QuickTime videi (MP4/MOV),"
            Write-Host "        Google Photos JSON, Adobe XMP a DJI SRT titulku k videim."
            Write-Host "      - Deduplikuje shodne zaznamy s GNSS (prvni G, dalsi D) a vse seradi dle data."
            Write-Host "      - Obsahuje VSECHNY soubory: G=unikat s GNSS (mapa), S=bez GNSS, D=duplicita s GNSS."
            Write-Host "      - Vystupni soubor: " -NoNewline; Write-Host "Mapa_Fotek_data_YYYYMMDD.txt" -ForegroundColor Cyan
            Write-Host "      - Format vystupu : JavaScriptovy datovy soubor (window.MAPA_FOTEK_DATA)"
            Write-Host "        Sloupce oddelene strednikem: DATUM_CAS; NAZEV; LAT; LON; BAJTY; CESTA; STAV"
            Write-Host "        Tento soubor primo nacita a vizualizuje mapa '" -NoNewline
            Write-Host "Mapa_Fotek.html" -ForegroundColor Cyan -NoNewline
            Write-Host "'."
            Write-Host ""
            Write-Host "  [2] Generovat data fotek (vybrat konkretni podslozku)" -ForegroundColor Green
            Write-Host "      - Otevre interaktivni pruzkumnik pro vyber konkretni slozky (napr. 1 rok)."
            Write-Host "      - Zpracuje pouze zvolenou podslozku a vytvori samostatny datovy soubor."
            Write-Host "      - Vystupni soubor: " -NoNewline; Write-Host "Mapa_Fotek_data_YYYYMMDD_NazevSlozky.txt" -ForegroundColor Cyan
            Write-Host "      - Format vystupu : Shodny s volbou [1], urceny pro dilci zobrazeni."
            Write-Host ""
            Write-Host "  [3] Generovat statistiku archivu fotek" -ForegroundColor Green
            Write-Host "      - Detailne zanalyzuje strukturu vsech slozek s medii v archivu."
            Write-Host "      - Spocita pocty souboru, velikost v bajtech i GB a najde nejstarsi"
            Write-Host "        a nejnovejsi soubor v kazde slozce i celkove (radek CELKEM)."
            Write-Host "      - Vystupni soubor: " -NoNewline; Write-Host "Mapa_Fotek_statistika_YYYYMMDD.csv" -ForegroundColor Cyan
            Write-Host "      - Format vystupu : Tabulkovy CSV soubor (UTF-8 s BOM pro Excel)"
            Write-Host "        Tabulka 1: Detailni prehled vsech jednotlivych podslozek"
            Write-Host "        Tabulka 2: Souhrn hlavnich slozek 1. urovne vcetne jejich podslozek"
            Write-Host ""
            Write-Host " PODPOROVANE FORMATY:" -ForegroundColor Yellow
            Write-Host "  - Fotky  : JPG, JPEG, HEIC, HEIF, AVIF, PNG, TIF, TIFF, BMP, GIF, WEBP"
            Write-Host "  - RAW    : DNG, CR2, CR3, NEF, ARW, RAF, ORF, RW2, PEF, SRW"
            Write-Host "  - Videa  : MP4, MOV, M4V, AVI, MKV, WMV, 3GP, FLV, MTS, M2TS, MPG, MPEG"
            Write-Host "  - Meta   : JSON (Google Photos), XMP (Adobe), SRT (DJI dron)"
            Write-Host "  - Odpad  : Thumbs.db, .picasa.ini, .tmp, .thm a skripty jsou ignorovany"
            Write-Host ""
            Write-Host "================================================================" -ForegroundColor Cyan
            Write-Host "  [K/Q] Zpet do hlavni nabidky    " -NoNewline -ForegroundColor Yellow
            Write-Host "[0] Ukoncit program" -ForegroundColor Red
            Write-Host "================================================================" -ForegroundColor Cyan
        }
        while ($true) {
            $pk = $null
            try {
                if ([Console]::KeyAvailable) { $pk = [Console]::ReadKey($true).KeyChar }
            } catch {
                $sel = Read-Host
                if ($sel) { $pk = $sel.Trim()[0] } else { $pk = 'K' }
            }
            if ($pk -eq '0') { [Environment]::Exit(0) }
            if ($pk -eq 'k' -or $pk -eq 'K' -or $pk -eq 'q' -or $pk -eq 'Q' -or $pk -eq [char]13 -or $pk -eq [char]10) {
                break
            }
            Start-Sleep -Milliseconds 100
        }
        continue mainLoop
    }

    if ($menuChoice -eq '2') {
        $chosen = Select-TargetFolder $targetDir
        if ($null -eq $chosen) {
            Write-Host ""
            Write-Host " Navrat do hlavni nabidky..." -ForegroundColor Yellow
            Start-Sleep -Milliseconds 700
            continue mainLoop
        }
        $targetDir = $chosen.TrimEnd('\') + '\'
        $relSegs = $chosen.Substring($scanRoot.Length).TrimStart('\').Split('\') |
                   ForEach-Object { ($_ -replace '[. ]+$', '') } |
                   Where-Object { $_ -ne '' }
        if ($relSegs) { $pickedSuffix = "_" + ($relSegs -join '_') }
    }

    # ------------------------------------------------------------------
    # VETEV VOLBY [3]: Vytvoreni statistiky slozek
    # ------------------------------------------------------------------
    if ($menuChoice -eq '3') {
        Clear-Host
        Write-ProgramBanner
        Write-Host ""
        if ($isEn) {
            Write-Host " Archive folder: $targetDir" -ForegroundColor White
            Write-Host " Mode          : GENERATE STATISTICS (all folders with files)" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "[1/2] Analyzing folder structure and generating statistics..." -ForegroundColor Yellow
        } else {
            Write-Host " Slozka archivu: $targetDir" -ForegroundColor White
            Write-Host " Rezim         : VYTVORENI STATISTIKY (vsechny slozky se soubory)" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "[1/2] Analyzuji strukturu slozek a generuji statistiku..." -ForegroundColor Yellow
        }

        [UnifiedScanner]::IsEnglish = $isEn
        $swStat = [System.Diagnostics.Stopwatch]::StartNew()
        $folderStats = [UnifiedScanner]::GenerateFolderStatistics($targetDir)
        $swStat.Stop()

        $todayStr = (Get-Date).ToString("yyyyMMdd")
        $timestampHeader = (Get-Date).ToString("dd.MM.yyyy HH:mm:ss")
        $statFileName = "Mapa_Fotek_statistika_${todayStr}.csv"
        $statFilePath = Join-Path $outputDir $statFileName

        # Vypocet celkovych souctu a globalnich extremu datumu
        $totalStatFiles = 0
        [long]$totalStatBytes = 0
        $globalOldestFileStr = ""
        $globalNewestFileStr = ""
        foreach ($st in $folderStats) {
            $totalStatFiles += $st.FileCount
            $totalStatBytes += $st.TotalSizeBytes
            if ($st.OldestFileStr -ne "-" -and $st.OldestFileStr -ne "") {
                if ($globalOldestFileStr -eq "" -or [string]::Compare($st.OldestFileStr, $globalOldestFileStr, [StringComparison]::Ordinal) -lt 0) {
                    $globalOldestFileStr = $st.OldestFileStr
                }
            }
            if ($st.NewestFileStr -ne "-" -and $st.NewestFileStr -ne "") {
                if ($globalNewestFileStr -eq "" -or [string]::Compare($st.NewestFileStr, $globalNewestFileStr, [StringComparison]::Ordinal) -gt 0) {
                    $globalNewestFileStr = $st.NewestFileStr
                }
            }
        }
        if ($globalOldestFileStr -eq "") { $globalOldestFileStr = "-" }
        if ($globalNewestFileStr -eq "") { $globalNewestFileStr = "-" }
        $totalGbStr = "{0:N2} GB" -f ($totalStatBytes / 1073741824)

        # Vypocet maximalnich sirek sloupcu pro Tabulku 1
        $h1 = "CESTA_SLOZKY"
        $h2 = "NEJSTARSI_SOUBOR"
        $h3 = "NEJNOVEJSI_SOUBOR"
        $h4 = "POCET_SOUBORU"
        $h5 = "VELIKOST_BAJTY"
        $h6 = "VELIKOST_GB"

        $w1 = [Math]::Max($h1.Length, "CELKEM".Length)
        $w2 = [Math]::Max($h2.Length, $globalOldestFileStr.Length)
        $w3 = [Math]::Max($h3.Length, $globalNewestFileStr.Length)
        $w4 = [Math]::Max($h4.Length, "$totalStatFiles".Length)
        $w5 = [Math]::Max($h5.Length, "$totalStatBytes".Length)
        $w6 = [Math]::Max($h6.Length, $totalGbStr.Length)

        foreach ($st in $folderStats) {
            $cntStr  = "$($st.FileCount)"
            $sizeStr = "$($st.TotalSizeBytes)"
            $gbStr   = "{0:N2} GB" -f ($st.TotalSizeBytes / 1073741824)
            if ($st.FolderPathKey.Length -gt $w1) { $w1 = $st.FolderPathKey.Length }
            if ($st.OldestFileStr.Length -gt $w2) { $w2 = $st.OldestFileStr.Length }
            if ($st.NewestFileStr.Length -gt $w3) { $w3 = $st.NewestFileStr.Length }
            if ($cntStr.Length -gt $w4)          { $w4 = $cntStr.Length }
            if ($sizeStr.Length -gt $w5)         { $w5 = $sizeStr.Length }
            if ($gbStr.Length -gt $w6)           { $w6 = $gbStr.Length }
        }

        $sb = [System.Text.StringBuilder]::new()
        $sb.AppendLine("// $statFileName") | Out-Null
        $sb.AppendLine("// Autor: Jan BARTUNEK | Verze: $scriptVersion ($scriptDate)") | Out-Null
        $sb.AppendLine("// Vygenerovano: $timestampHeader") | Out-Null
        $sb.AppendLine("// Sloupce: 1. CESTA_SLOZKY | 2. NEJSTARSI_SOUBOR | 3. NEJNOVEJSI_SOUBOR | 4. POCET_SOUBORU | 5. VELIKOST_BAJTY | 6. VELIKOST_GB") | Out-Null
        $fileHeader = $h1.PadRight($w1) + "; " + $h2.PadRight($w2) + "; " + $h3.PadRight($w3) + "; " + $h4.PadLeft($w4) + "; " + $h5.PadLeft($w5) + "; " + $h6.PadLeft($w6)
        $sb.AppendLine($fileHeader) | Out-Null

        foreach ($st in $folderStats) {
            $gbStr = "{0:N2} GB" -f ($st.TotalSizeBytes / 1073741824)
            $line = $st.FolderPathKey.PadRight($w1) + "; " + $st.OldestFileStr.PadRight($w2) + "; " + $st.NewestFileStr.PadRight($w3) + "; " + ("$($st.FileCount)").PadLeft($w4) + "; " + ("$($st.TotalSizeBytes)").PadLeft($w5) + "; " + $gbStr.PadLeft($w6)
            $sb.AppendLine($line) | Out-Null
        }

        # Posledni radek Tabulky 1 v CSV: CELKEM
        $fileTotalLine = "CELKEM".PadRight($w1) + "; " + $globalOldestFileStr.PadRight($w2) + "; " + $globalNewestFileStr.PadRight($w3) + "; " + ("$totalStatFiles").PadLeft($w4) + "; " + ("$totalStatBytes").PadLeft($w5) + "; " + $totalGbStr.PadLeft($w6)
        $sb.AppendLine($fileTotalLine) | Out-Null

        # ------------------------------------------------------------------
        # TABULKA 2: Agregace pro podslozky 1. radu (hlavni slozky vcetne vsech podslozek)
        # ------------------------------------------------------------------
        $topLevelGroups = [System.Collections.Generic.Dictionary[string, [PSCustomObject]]]::new([StringComparer]::OrdinalIgnoreCase)

        foreach ($st in $folderStats) {
            $rel = $st.RelativePath.TrimStart('\', '/')
            $topName = ""
            $sepIdx = $rel.IndexOfAny([char[]]@('\', '/'))
            if ($sepIdx -ge 0) {
                $topName = $rel.Substring(0, $sepIdx)
            } else {
                $topName = $rel
            }
            if ([string]::IsNullOrWhiteSpace($topName)) {
                $topName = (Split-Path -Path $targetDir.TrimEnd('\', '/') -Leaf)
                if ([string]::IsNullOrWhiteSpace($topName)) { $topName = "Koren" }
            }

            if (-not $topLevelGroups.ContainsKey($topName)) {
                $topLevelGroups[$topName] = [PSCustomObject]@{
                    FolderName     = $topName
                    FileCount      = [long]0
                    TotalSizeBytes = [long]0
                    OldestFileStr  = ""
                    NewestFileStr  = ""
                }
            }

            $grp = $topLevelGroups[$topName]
            $grp.FileCount += $st.FileCount
            $grp.TotalSizeBytes += $st.TotalSizeBytes

            # Oldest timestamp min
            if ($st.OldestFileStr -ne "-" -and $st.OldestFileStr -ne "") {
                if ($grp.OldestFileStr -eq "" -or [string]::Compare($st.OldestFileStr, $grp.OldestFileStr, [StringComparison]::Ordinal) -lt 0) {
                    $grp.OldestFileStr = $st.OldestFileStr
                }
            }
            # Newest timestamp max
            if ($st.NewestFileStr -ne "-" -and $st.NewestFileStr -ne "") {
                if ($grp.NewestFileStr -eq "" -or [string]::Compare($st.NewestFileStr, $grp.NewestFileStr, [StringComparison]::Ordinal) -gt 0) {
                    $grp.NewestFileStr = $st.NewestFileStr
                }
            }
        }

        $topLevelList = [System.Collections.Generic.List[PSCustomObject]]::new($topLevelGroups.Values)
        $topLevelList.Sort({ [string]::Compare($args[0].FolderName, $args[1].FolderName, [StringComparison]::OrdinalIgnoreCase) })

        foreach ($grp in $topLevelList) {
            if ($grp.OldestFileStr -eq "") { $grp.OldestFileStr = "-" }
            if ($grp.NewestFileStr -eq "") { $grp.NewestFileStr = "-" }
        }

        $h1_2 = "HLAVNI_SLOZKA"
        $h2_2 = "NEJSTARSI_SOUBOR"
        $h3_2 = "NEJNOVEJSI_SOUBOR"
        $h4_2 = "POCET_SOUBORU"
        $h5_2 = "VELIKOST_BAJTY"
        $h6_2 = "VELIKOST_GB"

        $w1_2 = [Math]::Max($h1_2.Length, "CELKEM".Length)
        $w2_2 = [Math]::Max($h2_2.Length, $globalOldestFileStr.Length)
        $w3_2 = [Math]::Max($h3_2.Length, $globalNewestFileStr.Length)
        $w4_2 = [Math]::Max($h4_2.Length, "$totalStatFiles".Length)
        $w5_2 = [Math]::Max($h5_2.Length, "$totalStatBytes".Length)
        $w6_2 = [Math]::Max($h6_2.Length, $totalGbStr.Length)

        foreach ($grp in $topLevelList) {
            $cntStr  = "$($grp.FileCount)"
            $sizeStr = "$($grp.TotalSizeBytes)"
            $gbStr   = "{0:N2} GB" -f ($grp.TotalSizeBytes / 1073741824)
            if ($grp.FolderName.Length -gt $w1_2)    { $w1_2 = $grp.FolderName.Length }
            if ($grp.OldestFileStr.Length -gt $w2_2) { $w2_2 = $grp.OldestFileStr.Length }
            if ($grp.NewestFileStr.Length -gt $w3_2) { $w3_2 = $grp.NewestFileStr.Length }
            if ($cntStr.Length -gt $w4_2)           { $w4_2 = $cntStr.Length }
            if ($sizeStr.Length -gt $w5_2)          { $w5_2 = $sizeStr.Length }
            if ($gbStr.Length -gt $w6_2)            { $w6_2 = $gbStr.Length }
        }

        # Zapis do CSV: 2 prazdne radky a druha tabulka
        $sb.AppendLine() | Out-Null
        $sb.AppendLine() | Out-Null
        $sb.AppendLine("// STATISTIKA HLAVNICH SLOZEK (1. UROVEN VCETNE VSECH PODSLOZEK)") | Out-Null
        $sb.AppendLine("// Sloupce: 1. HLAVNI_SLOZKA | 2. NEJSTARSI_SOUBOR | 3. NEJNOVEJSI_SOUBOR | 4. POCET_SOUBORU | 5. VELIKOST_BAJTY | 6. VELIKOST_GB") | Out-Null
        $fileHeader2 = $h1_2.PadRight($w1_2) + "; " + $h2_2.PadRight($w2_2) + "; " + $h3_2.PadRight($w3_2) + "; " + $h4_2.PadLeft($w4_2) + "; " + $h5_2.PadLeft($w5_2) + "; " + $h6_2.PadLeft($w6_2)
        $sb.AppendLine($fileHeader2) | Out-Null

        foreach ($grp in $topLevelList) {
            $gbStr = "{0:N2} GB" -f ($grp.TotalSizeBytes / 1073741824)
            $line2 = $grp.FolderName.PadRight($w1_2) + "; " + $grp.OldestFileStr.PadRight($w2_2) + "; " + $grp.NewestFileStr.PadRight($w3_2) + "; " + ("$($grp.FileCount)").PadLeft($w4_2) + "; " + ("$($grp.TotalSizeBytes)").PadLeft($w5_2) + "; " + $gbStr.PadLeft($w6_2)
            $sb.AppendLine($line2) | Out-Null
        }

        # Posledni radek Table 2 v CSV: CELKEM
        $fileTotalLine2 = "CELKEM".PadRight($w1_2) + "; " + $globalOldestFileStr.PadRight($w2_2) + "; " + $globalNewestFileStr.PadRight($w3_2) + "; " + ("$totalStatFiles").PadLeft($w4_2) + "; " + ("$totalStatBytes").PadLeft($w5_2) + "; " + $totalGbStr.PadLeft($w6_2)
        $sb.AppendLine($fileTotalLine2) | Out-Null

        $utf8Bom = [System.Text.UTF8Encoding]::new($true)
        [System.IO.File]::WriteAllText($statFilePath, $sb.ToString(), $utf8Bom)

        try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}

        Write-Host ""
        Write-Host "================================================================" -ForegroundColor Green
        if ($isEn) {
            Write-Host " STATISTICS COMPLETED SUCCESSFULLY!" -ForegroundColor Green
            Write-Host " Generation time        : $timestampHeader" -ForegroundColor White
            Write-Host (" Total folders with data: {0:N0}" -f $folderStats.Count) -ForegroundColor White
            Write-Host (" Total main folders     : {0:N0}" -f $topLevelList.Count) -ForegroundColor White
            Write-Host (" Total files            : {0:N0}" -f $totalStatFiles) -ForegroundColor White
            Write-Host (" Total data size        : {0} ({1:N0} B)" -f (Format-FileSize $totalStatBytes), $totalStatBytes) -ForegroundColor White
            Write-Host (" Processing time        : {0:N1} s" -f $swStat.Elapsed.TotalSeconds) -ForegroundColor White
            Write-Host " Output file            : $statFileName" -ForegroundColor White
        } else {
            Write-Host " STATISTIKA DOKONCENA USPESNE!" -ForegroundColor Green
            Write-Host " Cas vygenerovani       : $timestampHeader" -ForegroundColor White
            Write-Host (" Celkem slozek s daty   : {0:N0}" -f $folderStats.Count) -ForegroundColor White
            Write-Host (" Celkem hlavnich slozek : {0:N0}" -f $topLevelList.Count) -ForegroundColor White
            Write-Host (" Celkem souboru         : {0:N0}" -f $totalStatFiles) -ForegroundColor White
            Write-Host (" Celkovy objem dat      : {0} ({1:N0} B)" -f (Format-FileSize $totalStatBytes), $totalStatBytes) -ForegroundColor White
            Write-Host (" Doba zpracovani        : {0:N1} s" -f $swStat.Elapsed.TotalSeconds) -ForegroundColor White
            Write-Host " Vystupni soubor        : $statFileName" -ForegroundColor White
        }
        Write-Host "================================================================" -ForegroundColor Green
        Write-Host ""

        # Vypis Tabulky 1 do konzole
        if ($isEn) {
            Write-Host "--- DETAILED STATISTICS BY FOLDER ---" -ForegroundColor Cyan
        } else {
            Write-Host "--- DETAILNI STATISTIKA PODLE SLOZEK ---" -ForegroundColor Cyan
        }

        $h4Console = if ($isEn) { "COUNT" } else { "POCET" }
        $w4Console = [Math]::Max($h4Console.Length, ("{0:N0}" -f $totalStatFiles).Length)
        foreach ($st in $folderStats) {
            $cntStr = "{0:N0}" -f $st.FileCount
            if ($cntStr.Length -gt $w4Console) { $w4Console = $cntStr.Length }
        }

        # Pokusit se rozsirit sirku bufferu konzole
        try {
            $maxTableWidth = [Math]::Max($w1 + $w2 + $w3 + $w4Console + $w5 + $w6, $w1_2 + $w2_2 + $w3_2 + $w4Console + $w5_2 + $w6_2) + 20
            if ($Host.UI.RawUI.BufferSize.Width -lt $maxTableWidth) {
                $bSize = $Host.UI.RawUI.BufferSize
                $bSize.Width = $maxTableWidth + 5
                $Host.UI.RawUI.BufferSize = $bSize
            }
        } catch {}

        $consoleHeader = $h1.PadRight($w1) + " | " + $h2.PadRight($w2) + " | " + $h3.PadRight($w3) + " | " + $h4Console.PadLeft($w4Console) + " | " + $h5.PadLeft($w5) + " | " + $h6.PadLeft($w6)
        $sepLine = "-" * $consoleHeader.Length

        Write-Host $consoleHeader -ForegroundColor Yellow
        Write-Host $sepLine -ForegroundColor Gray

        foreach ($st in $folderStats) {
            $cntStr     = "{0:N0}" -f $st.FileCount
            $sizeStr    = "$($st.TotalSizeBytes)"
            $gbStr      = "{0:N2} GB" -f ($st.TotalSizeBytes / 1073741824)
            $row = $st.FolderPathKey.PadRight($w1) + " | " + $st.OldestFileStr.PadRight($w2) + " | " + $st.NewestFileStr.PadRight($w3) + " | " + $cntStr.PadLeft($w4Console) + " | " + $sizeStr.PadLeft($w5) + " | " + $gbStr.PadLeft($w6)
            Write-Host $row
        }
        Write-Host $sepLine -ForegroundColor Gray

        # Posledni radek: CELKEM
        $totalConsoleRow = "CELKEM".PadRight($w1) + " | " + $globalOldestFileStr.PadRight($w2) + " | " + $globalNewestFileStr.PadRight($w3) + " | " + ("{0:N0}" -f $totalStatFiles).PadLeft($w4Console) + " | " + ("$totalStatBytes").PadLeft($w5) + " | " + $totalGbStr.PadLeft($w6)
        Write-Host $totalConsoleRow -ForegroundColor Green
        Write-Host $sepLine -ForegroundColor Gray

        # 2 vynechane radky
        Write-Host ""
        Write-Host ""

        # Vypis Tabulky 2 do konzole
        if ($isEn) {
            Write-Host "--- MAIN FOLDERS STATISTICS (1ST LEVEL INCLUDING ALL SUBFOLDERS) ---" -ForegroundColor Cyan
        } else {
            Write-Host "--- STATISTIKA HLAVNICH SLOZEK (1. UROVEN VCETNE VSECH PODSLOZEK) ---" -ForegroundColor Cyan
        }

        $w4Console2 = [Math]::Max($h4Console.Length, ("{0:N0}" -f $totalStatFiles).Length)
        foreach ($grp in $topLevelList) {
            $cntStr = "{0:N0}" -f $grp.FileCount
            if ($cntStr.Length -gt $w4Console2) { $w4Console2 = $cntStr.Length }
        }

        $consoleHeader2 = $h1_2.PadRight($w1_2) + " | " + $h2_2.PadRight($w2_2) + " | " + $h3_2.PadRight($w3_2) + " | " + $h4Console.PadLeft($w4Console2) + " | " + $h5_2.PadLeft($w5_2) + " | " + $h6_2.PadLeft($w6_2)
        $sepLine2 = "-" * $consoleHeader2.Length

        Write-Host $consoleHeader2 -ForegroundColor Yellow
        Write-Host $sepLine2 -ForegroundColor Gray

        foreach ($grp in $topLevelList) {
            $cntStr  = "{0:N0}" -f $grp.FileCount
            $sizeStr = "$($grp.TotalSizeBytes)"
            $gbStr   = "{0:N2} GB" -f ($grp.TotalSizeBytes / 1073741824)
            $row2 = $grp.FolderName.PadRight($w1_2) + " | " + $grp.OldestFileStr.PadRight($w2_2) + " | " + $grp.NewestFileStr.PadRight($w3_2) + " | " + $cntStr.PadLeft($w4Console2) + " | " + $sizeStr.PadLeft($w5_2) + " | " + $gbStr.PadLeft($w6_2)
            Write-Host $row2
        }
        Write-Host $sepLine2 -ForegroundColor Gray

        # Posledni radek Tabulky 2: CELKEM
        $totalConsoleRow2 = "CELKEM".PadRight($w1_2) + " | " + $globalOldestFileStr.PadRight($w2_2) + " | " + $globalNewestFileStr.PadRight($w3_2) + " | " + ("{0:N0}" -f $totalStatFiles).PadLeft($w4Console2) + " | " + ("$totalStatBytes").PadLeft($w5_2) + " | " + $totalGbStr.PadLeft($w6_2)
        Write-Host $totalConsoleRow2 -ForegroundColor Green
        Write-Host $sepLine2 -ForegroundColor Gray
        Write-Host ""

        Write-Host "================================================================" -ForegroundColor Cyan
        if ($isEn) {
            Write-Host "  [K/Q] Back to main menu    " -NoNewline -ForegroundColor Yellow
            Write-Host "[Enter / any key] Exit" -ForegroundColor Red
        } else {
            Write-Host "  [K/Q] Zpet do hlavni nabidky    " -NoNewline -ForegroundColor Yellow
            Write-Host "[Enter / libovolna klavesa] Ukoncit" -ForegroundColor Red
        }
        Write-Host "================================================================" -ForegroundColor Cyan
        $promptLabel = if ($isEn) { "  Choice" } else { "  Volba" }
        $post = Read-Host $promptLabel
        if ($null -ne $post -and ($post.Trim().ToUpper() -eq 'K' -or $post.Trim().ToUpper() -eq 'Q' -or $post.Trim().ToUpper() -eq 'M' -or $post.Trim() -eq '1')) {
            continue mainLoop
        }
        break mainLoop
    }

    # ------------------------------------------------------------------
    # VETEV VOLEB [1] a [2]: Sken fotek a generovani TXT
    # ------------------------------------------------------------------
    Clear-Host
    Write-ProgramBanner
    Write-Host ""
    if ($isEn) {
        Write-Host " Photo folder: $targetDir" -ForegroundColor White
        Write-Host " Mode        : READ-ONLY (no photos are modified)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "[1/3] Scanning folders (ALL files incl. without GNSS), loading EXIF GNSS, Google JSON, Adobe XMP..." -ForegroundColor Yellow
    } else {
        Write-Host " Slozka fotek: $targetDir" -ForegroundColor White
        Write-Host " Rezim       : POUZE PRO CTENI (zadne fotky se nemeni)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "[1/3] Skenuji slozky (VSECHNY soubory vcetne bez GNSS), nacitam EXIF GNSS, Google JSON, Adobe XMP..." -ForegroundColor Yellow
    }

    [UnifiedScanner]::IsEnglish = $isEn
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $stats = [UnifiedScanner]::ScanAll($targetDir)
    $sw.Stop()

    $gpsRecords     = $stats.GpsRecords
    $dupRecords     = $stats.DupRecords
    $noGpsRecords   = $stats.NoGpsRecords
    $allRecords     = $stats.AllRecords
    $gpsBeforeDedup = $stats.GpsBeforeDedup
    $totalCount     = $stats.TotalFilesScanned
    $totalBytes     = $stats.TotalBytesScanned
    $formattedTotalBytes = Format-FileSize $totalBytes
    $duplicatesRemoved = $gpsBeforeDedup - $gpsRecords.Count
    if ($null -eq $dupRecords) { $dupRecords = @() }
    if ($null -eq $noGpsRecords) { $noGpsRecords = @() }
    if ($null -eq $allRecords) { $allRecords = @($gpsRecords) + @($dupRecords) + @($noGpsRecords) }

    if ($isEn) {
        Write-Host ("   Total files in folders     : {0:N0}" -f $totalCount) -ForegroundColor Green
        Write-Host ("   Photos with GNSS data      : {0:N0}" -f $gpsBeforeDedup) -ForegroundColor Green
        Write-Host ("   Unique for map (G)         : {0:N0}  (duplicates D: {1:N0}, without GNSS S: {2:N0})" -f $gpsRecords.Count, $dupRecords.Count, $noGpsRecords.Count) -ForegroundColor Green
        Write-Host ("   Total file size            : {0}  (scan time: {1:N1} s)" -f $formattedTotalBytes, $sw.Elapsed.TotalSeconds) -ForegroundColor Green
    } else {
        Write-Host ("   Celkem souboru ve slozkach : {0:N0}" -f $totalCount) -ForegroundColor Green
        Write-Host ("   Z toho fotek s udaji o GNSS: {0:N0}" -f $gpsBeforeDedup) -ForegroundColor Green
        Write-Host ("   Unikatnich pro mapu (G)    : {0:N0}  (duplicity D: {1:N0}, bez GNSS S: {2:N0})" -f $gpsRecords.Count, $dupRecords.Count, $noGpsRecords.Count) -ForegroundColor Green
        Write-Host ("   Celkovy objem souboru      : {0}  (cas skenu: {1:N1} s)" -f $formattedTotalBytes, $sw.Elapsed.TotalSeconds) -ForegroundColor Green
    }

    # Souhrn nečitelných souborů (např. HEIC bez nainstalovaného kodeku)
    $readFailCount = [UnifiedScanner]::ReadFailCount
    if ($readFailCount -gt 0) {
        $failParts = @()
        foreach ($kv in [UnifiedScanner]::FailByExt.GetEnumerator()) {
            $failParts += ("{0}x {1}" -f $kv.Value, $kv.Key.ToUpperInvariant())
        }
        if ($isEn) {
            Write-Host ("   Failed to read             : {0:N0}  ({1})" -f $readFailCount, ($failParts -join ", ")) -ForegroundColor DarkYellow
            foreach ($extKey in [UnifiedScanner]::FailByExt.Keys) {
                if ($extKey -eq ".heic" -or $extKey -eq ".heif") {
                    Write-Host "   Tip: to read iPhone (.HEIC) photos, install 'HEIF Image Extensions' from Microsoft Store" -ForegroundColor Cyan
                    break
                }
            }
        } else {
            Write-Host ("   Nepodarilo se precist      : {0:N0}  ({1})" -f $readFailCount, ($failParts -join ", ")) -ForegroundColor DarkYellow
            foreach ($extKey in [UnifiedScanner]::FailByExt.Keys) {
                if ($extKey -eq ".heic" -or $extKey -eq ".heif") {
                    Write-Host "   Tip: pro cteni iPhone fotek (.HEIC) nainstalujte z Microsoft Store rozsireni 'HEIF Image Extensions'" -ForegroundColor Cyan
                    break
                }
            }
        }
    }

    # Rekoncilace poctu souboru oproti Pruzkunikovi Windows (ten pocita uplne vsechno)
    $skipSidecars = [UnifiedScanner]::SkippedSidecars
    $skipOwn      = [UnifiedScanner]::SkippedOwnOutputs
    $skipJunkF    = [UnifiedScanner]::SkippedJunkFiles
    $skipJunkD    = [UnifiedScanner]::SkippedJunkDirs
    $enumErrors   = [UnifiedScanner]::EnumErrors
    if ($skipSidecars -gt 0 -or $skipOwn -gt 0 -or $skipJunkF -gt 0 -or $enumErrors -gt 0) {
        if ($isEn) {
            Write-Host ("   Excluded from count        : {0:N0}  (metadata {1:N0}, own outputs {2:N0}, system junk {3:N0})" -f ($skipSidecars + $skipOwn + $skipJunkF), $skipSidecars, $skipOwn, $skipJunkF) -ForegroundColor DarkGray
            if ($skipJunkD -gt 0) {
                Write-Host ("   Excluded junk folders      : {0:N0}" -f $skipJunkD) -ForegroundColor DarkGray
            }
            if ($enumErrors -gt 0) {
                Write-Host ("   Unreadable folders         : {0:N0}  (access denied / path too long)" -f $enumErrors) -ForegroundColor DarkYellow
            }
        } else {
            Write-Host ("   Vynechano z poctu          : {0:N0}  (metadata {1:N0}, vlastni vystupy {2:N0}, systemovy odpad {3:N0})" -f ($skipSidecars + $skipOwn + $skipJunkF), $skipSidecars, $skipOwn, $skipJunkF) -ForegroundColor DarkGray
            if ($skipJunkD -gt 0) {
                Write-Host ("   Vynechane slozky s odpadem : {0:N0}" -f $skipJunkD) -ForegroundColor DarkGray
            }
            if ($enumErrors -gt 0) {
                Write-Host ("   Neprojitelné slozky        : {0:N0}  (pristup odmitnut / prilis dlouha cesta)" -f $enumErrors) -ForegroundColor DarkYellow
            }
        }
    }

    $todayStr = (Get-Date).ToString("yyyyMMdd")
    $timestampHeader = (Get-Date).ToString("dd.MM.yyyy HH:mm:ss")
    $outFileName = "Mapa_Fotek_data_${todayStr}${pickedSuffix}.txt"

    Write-Host ""
    if ($isEn) {
        Write-Host "[2/3] Saving data to: $outFileName..." -ForegroundColor Yellow
    } else {
        Write-Host "[2/3] Ukladam data do: $outFileName..." -ForegroundColor Yellow
    }
    $nfi = [System.Globalization.NumberFormatInfo]::InvariantInfo
    $tab = [char]9
    $bt = [char]96

    $sb = [System.Text.StringBuilder]::new()
    $sb.AppendLine("// $outFileName") | Out-Null
    $sb.AppendLine("// Autor: Jan BARTUNEK | Verze: $scriptVersion ($scriptDate)") | Out-Null
    $sb.AppendLine("// Vygenerovano: $timestampHeader") | Out-Null
    $sb.AppendLine("// Sloupce: DATUM_CAS; `t NAZEV_SOUBORU; `t LATITUDE; `t LONGITUDE; `t VELIKOST_BAJTY; `t RELATIVNI_CESTA; `t STAV (G=GNSS unikat, S=bez GNSS, D=duplicita s GNSS)") | Out-Null
    $sb.AppendLine("window.MAPA_FOTEK_DATA = " + $bt) | Out-Null
    $sb.AppendLine("DATUM_CAS;" + $tab + "NAZEV_SOUBORU;" + $tab + "LATITUDE;" + $tab + "LONGITUDE;" + $tab + "VELIKOST_BAJTY;" + $tab + "RELATIVNI_CESTA;" + $tab + "STAV") | Out-Null

    foreach ($item in $allRecords) {
        $st = $item.Status
        if ([string]::IsNullOrEmpty($st)) { if ($item.HasGps) { $st = "G" } else { $st = "S" } }
        if ($st -eq "S") {
            $latStr = ""
            $lonStr = ""
        } else {
            $latStr = $item.Latitude.ToString("F6", $nfi)
            $lonStr = $item.Longitude.ToString("F6", $nfi)
        }
        $line = "{0};{1}{2};{1}{3};{1}{4};{1}{5};{1}{6};{1}{7}" -f $item.DateTakenStr, $tab, $item.FileName, $latStr, $lonStr, $item.FileSizeBytes, $item.RelativePath, $st
        $sb.AppendLine($line) | Out-Null
    }
    $sb.AppendLine($bt + ";") | Out-Null

    $txtContent = $sb.ToString()
    $utf8Bom = [System.Text.UTF8Encoding]::new($true)
    [System.IO.File]::WriteAllText((Join-Path $outputDir $outFileName), $txtContent, $utf8Bom)

    try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}

    if ($isEn) {
        Write-Host "[3/3] Done!" -ForegroundColor Yellow
    } else {
        Write-Host "[3/3] Hotovo!" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Green
    if ($isEn) {
        Write-Host " UPDATE COMPLETED SUCCESSFULLY!" -ForegroundColor Green
        Write-Host " Generation time     : $timestampHeader" -ForegroundColor White
        Write-Host ""
        Write-Host (" Total files         : {0:N0}" -f $totalCount) -ForegroundColor White
        Write-Host (" Photos with GNSS    : {0:N0}" -f $gpsBeforeDedup) -ForegroundColor White
        Write-Host (" Unique for map (G)  : {0:N0}  (D duplicates: {1:N0}, S without GNSS: {2:N0})" -f $gpsRecords.Count, $dupRecords.Count, $noGpsRecords.Count) -ForegroundColor White
        Write-Host (" Rows in output file : {0:N0}" -f $allRecords.Count) -ForegroundColor White
        Write-Host ""
        Write-Host (" Total data volume   : {0}" -f $formattedTotalBytes) -ForegroundColor White
        Write-Host " Output file         : $outFileName" -ForegroundColor White
        if ($readFailCount -gt 0) {
            Write-Host (" Failed to read      : {0:N0}  (missing codec or damaged file)" -f $readFailCount) -ForegroundColor Yellow
        }
    } else {
        Write-Host " AKTUALIZACE DOKONCENA USPESNE!" -ForegroundColor Green
        Write-Host " Cas vygenerovani    : $timestampHeader" -ForegroundColor White
        Write-Host ""
        Write-Host (" Celkem souboru      : {0:N0}" -f $totalCount) -ForegroundColor White
        Write-Host (" Fotek s GNSS        : {0:N0}" -f $gpsBeforeDedup) -ForegroundColor White
        Write-Host (" Unikatnich pro mapu (G): {0:N0}  (D duplicit: {1:N0}, S bez GNSS: {2:N0})" -f $gpsRecords.Count, $dupRecords.Count, $noGpsRecords.Count) -ForegroundColor White
        Write-Host (" Radku ve vystupnim souboru: {0:N0}" -f $allRecords.Count) -ForegroundColor White
        Write-Host ""
        Write-Host (" Celkovy datovy objem: {0}" -f $formattedTotalBytes) -ForegroundColor White
        Write-Host " Vystupni soubor     : $outFileName" -ForegroundColor White
        if ($readFailCount -gt 0) {
            Write-Host (" Nepodarilo se precist: {0:N0}  (viz souhrn vyse – chybi kodek nebo poskozeny soubor)" -f $readFailCount) -ForegroundColor Yellow
        }
    }
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host ""

    Write-Host "================================================================" -ForegroundColor Cyan
    if ($isEn) {
        Write-Host "  [K/Q] Back to main menu    " -NoNewline -ForegroundColor Yellow
        Write-Host "[Enter / any key] Exit" -ForegroundColor Red
    } else {
        Write-Host "  [K/Q] Zpet do hlavni nabidky    " -NoNewline -ForegroundColor Yellow
        Write-Host "[Enter / libovolna klavesa] Ukoncit" -ForegroundColor Red
    }
    Write-Host "================================================================" -ForegroundColor Cyan
    $promptLabel = if ($isEn) { "  Choice" } else { "  Volba" }
    $post = Read-Host $promptLabel
    if ($null -ne $post -and ($post.Trim().ToUpper() -eq 'K' -or $post.Trim().ToUpper() -eq 'Q' -or $post.Trim().ToUpper() -eq 'M' -or $post.Trim() -eq '1')) {
        continue mainLoop
    }
    break mainLoop
}
