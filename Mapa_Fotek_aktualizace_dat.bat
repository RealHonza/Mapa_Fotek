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

# Verze programu - jediny zdroj, pouziva se v banneru i ve vystupnim souboru
$scriptVersion = "2.21"
$scriptDate    = "25.10.2026"

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
    public double? Altitude { get; set; }  // Nadmorska vyska v metrech (null = neni v EXIF)
    public string RelativePath { get; set; }
    public string FileName { get; set; }
    public long FileSizeBytes { get; set; }
    public bool HasGps { get; set; }
    public string Status { get; set; }
    // Duveryhodnost DATUM_CAS (pro slouceni se sidecar souborem - vyhrava vyssi, pri shode vlastni soubor):
    //  0 = nahradni (nazev souboru / datum zmeny)
    //  1 = UTC cas prevedeny na pasmo PC (Google JSON photoTakenTime, video mvhd)
    //  2 = mistni cas porizeni (EXIF, XMP, Apple creationdate, titulky DJI SRT)
    public int DateQuality { get; set; }

    // Jednotne pravidlo pro nadmorskou vysku (vsechny zdroje: EXIF, XMP, Google JSON, video, SRT).
    // Vraci null (= pole zustane prazdne), kdyz je hodnota neplatna:
    //  - presne 0 = telefon vysku neurcil (EXIF 0/1), ne poloha u more; 0,01 nebo -0,03 jsou skutecna mereni
    //  - mimo rozsah -500 az 15 000 m (nejnize polozene misto na souse je Mrtve more cca -430 m,
    //    letova hladina do cca 12,5 km) = chybna hodnota
    // Kontrola se dela na surove hodnote pred zaokrouhlenim; platna hodnota se zaokrouhli na desetiny.
    public const double AltMin = -500.0;
    public const double AltMax = 15000.0;
    public static double? ValidAltitude(double raw)
    {
        if (double.IsNaN(raw) || double.IsInfinity(raw)) return null;
        if (raw == 0.0) return null;
        if (raw < AltMin || raw > AltMax) return null;
        return Math.Round(raw, 1);
    }
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
        // Standard EXIF = 3 hodnoty (stupne, minuty, sekundy); nektere nastroje zapisuji jen 2
        // (stupne, desetinne minuty) nebo 1 (desetinne stupne) - chybejici hodnoty = 0
        if (coords == null || coords.Length < 1) return null;
        double deg = DecodeRational(coords[0]);
        double min = coords.Length > 1 ? DecodeRational(coords[1]) : 0.0;
        double sec = coords.Length > 2 ? DecodeRational(coords[2]) : 0.0;

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
        // Ceska konvence - DEN PRVNI (pred mesicem-prvnim, aby nedochazelo k zamen!)
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
        // Lomitkove formaty - nejprve den-prvni (ceska/europska konvence)
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

    private static readonly Regex IsoDateRegex = new Regex(
        @"^(\d{4})[-:](\d{2})[-:](\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:[.,]\d+)?)?\s*(Z|[+-]\d{2}(?::?\d{2})?)?$",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    // Datum ve tvaru ISO 8601 -> "yyyyMMdd_HHmmss" (mistni cas porizeni), jinak null
    private static string ParseIsoWallClock(string s)
    {
        var m = IsoDateRegex.Match(s);
        if (!m.Success) return null;
        try
        {
            int sec = m.Groups[6].Success ? int.Parse(m.Groups[6].Value, CultureInfo.InvariantCulture) : 0;
            var dt = new DateTime(
                int.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture),
                int.Parse(m.Groups[2].Value, CultureInfo.InvariantCulture),
                int.Parse(m.Groups[3].Value, CultureInfo.InvariantCulture),
                int.Parse(m.Groups[4].Value, CultureInfo.InvariantCulture),
                int.Parse(m.Groups[5].Value, CultureInfo.InvariantCulture),
                sec, DateTimeKind.Unspecified);
            if (m.Groups[7].Success && m.Groups[7].Value.ToUpperInvariant() == "Z")
                dt = DateTime.SpecifyKind(dt, DateTimeKind.Utc).ToLocalTime();
            if (!IsValidYear(dt)) return null;
            return dt.ToString("yyyyMMdd_HHmmss", CultureInfo.InvariantCulture);
        }
        catch { return null; } // neplatne datum (napr. 2023-02-30) -> zkusi se dalsi formaty
    }

    // ------------------------------------------------------------------
    // Datum z NAZVU souboru (fotka/video bez data v metadatech)
    //  - datum+cas: IMG_20231015_143022, PXL_20231015_143022123 (ms), VID_20231015_143022,
    //    Screenshot_2023-10-15-14-30-22, photo_2023-10-15_14-30-22, signal-2023-10-15-143022,
    //    DJI_20231015143022_0001_D
    //  - datum: 20231015, IMG-20231015-WA0001, 2023-10-15, 2023_10_15, 2023.10.15
    //  - rok-mesic / rok (Dovolena_2019-08, Vanoce 1987): jen kdyz to NENI pocitadlo fotoaparatu
    //    (IMG_2034, DSC_1999, MVI_2015, DJI_2001 ...) a rok neni v budoucnosti (DSCN2050 apod.)
    //  - neexistujici datum (20230231) se nepouzije
    // ------------------------------------------------------------------
    private static readonly Regex FnDateTimeRegex = new Regex(
        @"(?<!\d)(19\d\d|20\d\d)[-_.]?(0[1-9]|1[0-2])[-_.]?(0[1-9]|[12]\d|3[01])[ _\-T.]?([01]\d|2[0-3])[-_.:]?([0-5]\d)[-_.:]?([0-5]\d)(?:\d{1,3})?(?!\d)",
        RegexOptions.Compiled);
    private static readonly Regex FnDateRegex = new Regex(
        @"(?<!\d)(19\d\d|20\d\d)([-_.]?)(0[1-9]|1[0-2])\2(0[1-9]|[12]\d|3[01])(?!\d)",
        RegexOptions.Compiled);
    private static readonly Regex FnYearMonthRegex = new Regex(
        @"(?<![A-Za-z0-9])(19\d\d|20\d\d)[-_.](0[1-9]|1[0-2])(?!\d)",
        RegexOptions.Compiled);
    private static readonly Regex FnYearRegex = new Regex(
        @"(?<![A-Za-z0-9])(19\d\d|20\d\d)(?!\d)",
        RegexOptions.Compiled);
    // Typicka pocitadla fotoaparatu/telefonu/kamer: prefix + 4 cislice (IMG_2034, kopie_DSC_1999 ...)
    private static readonly Regex FnCounterRegex = new Regex(
        @"(?<![A-Za-z0-9])(?:IMG|IMGP|DSC|DSCN|DSCF|DSCI|_DSC|DSC_|_MG|MVI|VID|MOV|MAH|PICT|PIC|CIMG|IMAG|HPIM|SAM|SDIM|DCP|DCIM|KIF|CRW|GOPR|GP|DJI|PANO|P|R|WP|CAM|SNC|EX|MG)[_\- ]?(\d{4})(?!\d)",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    private static bool FnYearOk(string y) { int v = int.Parse(y, CultureInfo.InvariantCulture); return v >= 1900 && v <= DateTime.Now.Year + 1; }

    // Plne datum+cas z nazvu (null = nazev ho neobsahuje)
    private static DateTime? ParseFileNameDateTime(string fileName)
    {
        foreach (Match m in FnDateTimeRegex.Matches(fileName))
        {
            if (!FnYearOk(m.Groups[1].Value)) continue;
            try
            {
                return new DateTime(int.Parse(m.Groups[1].Value), int.Parse(m.Groups[2].Value), int.Parse(m.Groups[3].Value),
                                    int.Parse(m.Groups[4].Value), int.Parse(m.Groups[5].Value), int.Parse(m.Groups[6].Value));
            }
            catch {}
        }
        return null;
    }

    public static string ParseFileNameDate(string fileName)
    {
        if (string.IsNullOrEmpty(fileName)) return null;
        string name = Path.GetFileNameWithoutExtension(fileName);

        DateTime? full = ParseFileNameDateTime(name);
        if (full.HasValue) return full.Value.ToString("yyyyMMdd_HHmmss", CultureInfo.InvariantCulture);

        foreach (Match m in FnDateRegex.Matches(name))
        {
            if (!FnYearOk(m.Groups[1].Value)) continue;
            try
            {
                var d = new DateTime(int.Parse(m.Groups[1].Value), int.Parse(m.Groups[3].Value), int.Parse(m.Groups[4].Value));
                return d.ToString("yyyyMMdd", CultureInfo.InvariantCulture) + "_000000";
            }
            catch {}
        }

        // pozice cislic pocitadel (IMG_2034 -> index 4), ty se jako rok nepouziji
        var counterPos = new HashSet<int>();
        foreach (Match cm in FnCounterRegex.Matches(name)) counterPos.Add(cm.Groups[1].Index);

        foreach (Match m in FnYearMonthRegex.Matches(name))
        {
            if (counterPos.Contains(m.Index) || !FnYearOk(m.Groups[1].Value)) continue;
            return m.Groups[1].Value + m.Groups[2].Value + "01_000000";
        }
        foreach (Match m in FnYearRegex.Matches(name))
        {
            if (counterPos.Contains(m.Index) || !FnYearOk(m.Groups[1].Value)) continue;
            return m.Groups[1].Value + "0101_000000";
        }
        return null;
    }

    public static string ParseDateTimeToFullStr(string dateTaken, string fileName, DateTime fileDate)
    {
        if (!string.IsNullOrWhiteSpace(dateTaken))
        {
            string s = dateTaken.Trim();
            DateTime dt;

            // 0) ISO 8601 / XMP s casovym pasmem nebo zlomky sekund (Lightroom, digiKam, telefony):
            //    "2023-10-15T14:30:22.45+02:00", "2023-10-15T14:30:22-04:00", "2023:10:15 14:30:22+0200"
            //    Ciselne pasmo = mistni cas fotoaparatu -> bere se cas tak, jak je zapsan (stejne jako EXIF),
            //    BEZ prepoctu na pasmo pocitace. "Z" (UTC) mistni cas neurcuje -> prevede se na pasmo PC.
            string iso = ParseIsoWallClock(s);
            if (iso != null) return iso;

            // 1) Presne zname formaty - pro nejednoznacne datumy ma prednost DEN PRVNI (ceska konvence),
            //    cimz se predchazi zamen mesice a dne pri prevodu na YYYYMMDD
            if (TryParseKnownFormats(s, out dt))
                return dt.ToString("yyyyMMdd_HHmmss", CultureInfo.InvariantCulture);

            // 2) Obecny parse ceske kultury (d.M.yyyy = den prvni)
            if (DateTime.TryParse(s, new CultureInfo("cs-CZ"), DateTimeStyles.None, out dt) && IsValidYear(dt))
                return dt.ToString("yyyyMMdd_HHmmss", CultureInfo.InvariantCulture);

            // 3) Posledni zachrana: invariantni kultura (mesic prvni - americka konvence)
            if (DateTime.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.None, out dt) && IsValidYear(dt))
                return dt.ToString("yyyyMMdd_HHmmss", CultureInfo.InvariantCulture);
        }

        string fromName = ParseFileNameDate(fileName);
        if (fromName != null) return fromName;

        return fileDate.ToString("yyyyMMdd_HHmmss", CultureInfo.InvariantCulture);
    }

    // Robustni dekodovani EXIF RATIONAL (GPSAltitude). WPF/WIC muze hodnotu vratit v vice
    // podobach: baleny long/ulong (num = low 32b, den = high 32b), ulong[] s jednim prvkem,
    // double (System.* dotazy) nebo retezec "num/den". Nevalidni hodnoty vraci null.
    private static double? UnpackUlongRational(ulong packed)
    {
        ulong num = packed & 0xFFFFFFFF;
        ulong den = (packed >> 32) & 0xFFFFFFFF;
        if (den == 0) return null;
        double val = (double)num / (double)den;
        if (double.IsNaN(val) || double.IsInfinity(val)) return null;
        return val;
    }

    private static double? DecodeExifRationalValue(object v)
    {
        try
        {
            if (v == null) return null;
            if (v is double) { double d = (double)v; if (double.IsNaN(d) || double.IsInfinity(d)) return null; return d; }
            if (v is float) { float f = (float)v; if (float.IsNaN(f) || float.IsInfinity(f)) return null; return f; }
            if (v is ulong[]) { ulong[] a = (ulong[])v; if (a.Length == 0) return null; return UnpackUlongRational(a[0]); }
            if (v is long[]) { long[] a = (long[])v; if (a.Length == 0) return null; return UnpackUlongRational(unchecked((ulong)a[0])); }
            if (v is long) return UnpackUlongRational(unchecked((ulong)(long)v));
            if (v is ulong) return UnpackUlongRational((ulong)v);
            if (v is string)
            {
                string s = ((string)v).Trim();
                int slash = s.IndexOf('/');
                if (slash > 0)
                {
                    double sn, sd;
                    if (double.TryParse(s.Substring(0, slash), NumberStyles.Any, CultureInfo.InvariantCulture, out sn) &&
                        double.TryParse(s.Substring(slash + 1), NumberStyles.Any, CultureInfo.InvariantCulture, out sd) && sd != 0)
                    {
                        double val = sn / sd;
                        if (double.IsNaN(val) || double.IsInfinity(val)) return null;
                        return val;
                    }
                }
                double plain;
                if (double.TryParse(s, NumberStyles.Any, CultureInfo.InvariantCulture, out plain) &&
                    !double.IsNaN(plain) && !double.IsInfinity(plain))
                    return plain;
                return null;
            }
            if (v is int || v is uint || v is short || v is ushort || v is byte) return Convert.ToDouble(v, CultureInfo.InvariantCulture);
        }
        catch {}
        return null;
    }

    // GPSAltitudeRef: 0 = nad morem, 1 = pod morem (WPF vraci byte, int, ulong i retezec)
    private static int DecodeAltitudeRef(object v)
    {
        try
        {
            if (v == null) return 0;
            if (v is byte[]) { byte[] b = (byte[])v; return b.Length > 0 ? b[0] : 0; }
            if (v is string) return ((string)v).Trim() == "1" ? 1 : 0;
            return Convert.ToInt32(v, CultureInfo.InvariantCulture);
        }
        catch { return 0; }
    }

    // DATUM_CAS z metadat fotky NEZAVISLE na jazyku a formatu data ve Windows.
    // (BitmapMetadata.DateTaken vraci DateTime.ToString() v regionalnim formatu uzivatele -
    //  napr. v en-US "10/5/2023 2:05:33 PM" se prohodil den a mesic, fi-FI/th-TH/fa-IR se nenacetly.)
    // Poradi: 1) EXIF DateTimeOriginal jako surovy retezec "yyyy:MM:dd HH:mm:ss" (JPEG i TIFF/RAW/HEIC)
    //         2) policy System.Photo.DateTaken jako FILETIME (stejny zdroj jako drive DateTaken,
    //            vcetne XMP), formatovany invariantne a v gregorianskem kalendari
    //         3) EXIF DateTimeDigitized (skenery, nektere fotoaparaty)
    // Vraci "yyyyMMdd_HHmmss" nebo null.
    private static string ReadPhotoDate(BitmapMetadata metadata)
    {
        string r = TryRawExifDate(metadata, "/app1/ifd/exif/{ushort=36867}", "/ifd/exif/{ushort=36867}");
        if (r != null) return r;

        try
        {
            object ft = MetaQuery(metadata, "System.Photo.DateTaken");
            if (ft is System.Runtime.InteropServices.ComTypes.FILETIME)
            {
                var t = (System.Runtime.InteropServices.ComTypes.FILETIME)ft;
                long ftVal = (((long)t.dwHighDateTime) << 32) + (uint)t.dwLowDateTime;
                if (ftVal > 0)
                {
                    DateTime d = DateTime.FromFileTime(ftVal);
                    if (IsValidYear(d)) return d.ToString("yyyyMMdd_HHmmss", CultureInfo.InvariantCulture);
                }
            }
        }
        catch {}

        return TryRawExifDate(metadata, "/app1/ifd/exif/{ushort=36868}", "/ifd/exif/{ushort=36868}");
    }

    // Surovy EXIF retezec data -> "yyyyMMdd_HHmmss"; prazdne/nulove hodnoty ("0000:00:00 00:00:00",
    // mezery) a nesmysly vraci null, aby se zkusil dalsi zdroj
    private static string TryRawExifDate(BitmapMetadata metadata, params string[] queries)
    {
        foreach (string q in queries)
        {
            string s = MetaQuery(metadata, q) as string;
            if (s == null) continue;
            s = s.Trim('\0', ' ');
            if (s.Length < 10 || s.StartsWith("0000", StringComparison.Ordinal)) continue;
            DateTime dt;
            if (TryParseKnownFormats(s, out dt))
                return dt.ToString("yyyyMMdd_HHmmss", CultureInfo.InvariantCulture);
            // nektere fotoaparaty pridavaji za sekundy zlomky nebo pasmo - vzit jen prvnich 19 znaku
            if (s.Length > 19 && TryParseKnownFormats(s.Substring(0, 19), out dt))
                return dt.ToString("yyyyMMdd_HHmmss", CultureInfo.InvariantCulture);
        }
        return null;
    }

    // POZNAMKA - KODEKY WINDOWS (zamerne se uzivateli nehlasi):
    // Fotky se ctou pres WIC (BitmapDecoder). Kdyz ve Windows chybi kodek, BitmapDecoder.Create vyhodi
    // vyjimku -> soubor se zapocita do ReadFailCount / FailByExt, skonci bez GNSS (S) a datum se vezme
    // z nazvu souboru / data zmeny (souradnice muze stale dodat Google JSON nebo XMP sidecar).
    // Potrebna rozsireni z Microsoft Store:
    //   HEIC/HEIF ............ "HEIF Image Extensions" (casto i "HEVC Video Extensions")
    //   AVIF ................. "AV1 Video Extension"
    //   CR2/CR3/NEF/ARW/RAF/ORF/RW2/PEF/SRW ... "Raw Image Extension"
    //   WebP ................. soucast novejsich Windows; u WebP a PNG WIC EXIF GPS casto nezpristupni
    // Moznost do budoucna: vlastni EXIF/TIFF parser jako zaloha (JPEG APP1, TIFF/RAW, HEIC box "Exif" -
    // EXIF je ve vsech techto formatech stejna TIFF struktura), ktery by na kodecich nezavisel.
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
                            // DATUM_CAS: cteme vzdy z EXIF, nezavisle na GPS i na jazyku Windows
                            string exifDate = ReadPhotoDate(metadata);
                            if (exifDate != null)
                            {
                                rec.DateTakenStr = exifDate;
                                rec.DateQuality = 2;
                            }

                            object latObj = null, lonObj = null, latRefObj = null, lonRefObj = null;
                            // JPEG: /app1/ifd/gps/..., TIFF/DNG/RAW: /ifd/gps/... - vyzkouset obe varianty.
                            // Standardni cesty {ushort=N} jsou prvni - neplatny dotaz WIC vyhodi (zachycenou)
                            // vyjimku, coz u velkych knihoven zbytecne zpomaluje; subifd zustava jen jako zaloha.
                            latObj    = MetaQuery(metadata, "/app1/ifd/gps/{ushort=2}", "/ifd/gps/{ushort=2}", "/app1/ifd/gps/subifd:{ulong=2}", "/ifd/gps/subifd:{ulong=2}");
                            latRefObj = MetaQuery(metadata, "/app1/ifd/gps/{ushort=1}", "/ifd/gps/{ushort=1}", "/app1/ifd/gps/subifd:{ulong=1}", "/ifd/gps/subifd:{ulong=1}");
                            lonObj    = MetaQuery(metadata, "/app1/ifd/gps/{ushort=4}", "/ifd/gps/{ushort=4}", "/app1/ifd/gps/subifd:{ulong=4}", "/ifd/gps/subifd:{ulong=4}");
                            lonRefObj = MetaQuery(metadata, "/app1/ifd/gps/{ushort=3}", "/ifd/gps/{ushort=3}", "/app1/ifd/gps/subifd:{ulong=3}", "/ifd/gps/subifd:{ulong=3}");

                            ulong[] latArray = latObj as ulong[];
                            ulong[] lonArray = lonObj as ulong[];
                            string latRef = latRefObj as string;
                            string lonRef = lonRefObj as string;

                            if (latArray != null && lonArray != null)
                            {
                                double? lat = ConvertGpsToDecimal(latArray, latRef);
                                double? lon = ConvertGpsToDecimal(lonArray, lonRef);

                                if (lat.HasValue && lon.HasValue && (Math.Abs(lat.Value) > 0.0001 || Math.Abs(lon.Value) > 0.0001)
                                    && Math.Abs(lat.Value) <= 90.0 && Math.Abs(lon.Value) <= 180.0)
                                {
                                    rec.Latitude = Math.Round(lat.Value, 6);
                                    rec.Longitude = Math.Round(lon.Value, 6);
                                    rec.HasGps = true;
                                }
                            }

                            // Zaloha: souradnice z XMP vlozeneho primo ve fotce (Lightroom, Fotky Windows/macOS,
                            // geotagovaci nastroje casto zapisuji polohu jen do XMP; PNG/WebP EXIF GPS nemivaji)
                            if (!rec.HasGps)
                            {
                                string xLatS = MetaQuery(metadata, "/xmp/exif:GPSLatitude", "/ifd/xmp/exif:GPSLatitude") as string;
                                string xLonS = MetaQuery(metadata, "/xmp/exif:GPSLongitude", "/ifd/xmp/exif:GPSLongitude") as string;
                                double? xLat = ParseXmpCoordinate(xLatS);
                                double? xLon = ParseXmpCoordinate(xLonS);
                                if (xLat.HasValue && xLon.HasValue && (Math.Abs(xLat.Value) > 0.0001 || Math.Abs(xLon.Value) > 0.0001)
                                    && Math.Abs(xLat.Value) <= 90.0 && Math.Abs(xLon.Value) <= 180.0)
                                {
                                    rec.Latitude = Math.Round(xLat.Value, 6);
                                    rec.Longitude = Math.Round(xLon.Value, 6);
                                    rec.HasGps = true;
                                }
                            }

                            // NADMORSKA_VYSKA: GPS tag 6 (RATIONAL) + tag 5 (ref: 0=nad morem, 1=pod morem).
                            // Zkousi se EXIF v JPEG i TIFF/RAW podobe a nakonec vlozeny XMP; vyska i ref
                            // se ctou vzdy ze stejneho zdroje. Nevalidni hodnota umozni zkuset dalsi zdroj.
                            double? altVal = null;
                            int altRef = 0;
                            string[][] altSources = new string[][] {
                                new string[] { "/app1/ifd/gps/{ushort=6}", "/app1/ifd/gps/{ushort=5}" },
                                new string[] { "/ifd/gps/{ushort=6}", "/ifd/gps/{ushort=5}" },
                                new string[] { "/app1/ifd/gps/subifd:{ulong=6}", "/app1/ifd/gps/subifd:{ulong=5}" },
                                new string[] { "/ifd/gps/subifd:{ulong=6}", "/ifd/gps/subifd:{ulong=5}" },
                                new string[] { "/xmp/exif:GPSAltitude", "/xmp/exif:GPSAltitudeRef" },
                                new string[] { "/ifd/xmp/exif:GPSAltitude", "/ifd/xmp/exif:GPSAltitudeRef" }
                            };
                            foreach (string[] src in altSources)
                            {
                                double? v = DecodeExifRationalValue(MetaQuery(metadata, src[0]));
                                if (!v.HasValue) continue;
                                altRef = DecodeAltitudeRef(MetaQuery(metadata, src[1]));
                                // ref=1 znamena pod morem - vysledek je vzdy zaporny
                                double signed = (altRef == 1) ? -Math.Abs(v.Value) : v.Value;
                                // Neplatna vyska (presne 0 / mimo rozsah) -> zkusit dalsi zdroj (napr. vlozene XMP)
                                altVal = PhotoRecordItem.ValidAltitude(signed);
                                if (!altVal.HasValue) continue;
                                break;
                            }
                            // Vyska se uklada vzdy: kdyz souradnice doda az sidecar (Google JSON / XMP), vlastni
                            // vyska fotky se zachova. U fotky, ktera zustane bez polohy (S), se pozdeji vymaze.
                            if (altVal.HasValue)
                                rec.Altitude = altVal;
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
        string pp;
        return ProcessGoogleJson(jsonPath, rootBase, out pp);
    }

    // Dekodovani retezce z JSON: \u0026, \", \\, \/ ...
    public static string JsonUnescape(string s)
    {
        if (s.IndexOf('\\') < 0) return s;
        return Regex.Replace(s, @"\\(u[0-9a-fA-F]{4}|.)", m =>
        {
            string e = m.Groups[1].Value;
            if (e.Length == 5) return ((char)Convert.ToInt32(e.Substring(1), 16)).ToString();
            switch (e[0]) { case 'n': return "\n"; case 't': return "\t"; case 'r': return "\r"; case 'b': return "\b"; case 'f': return "\f"; default: return e; }
        });
    }

    // Soubory, ke kterym Takeout zvlastni JSON nedava, ale patri k fotce: upravena kopie
    // (IMG_1234-edited.jpg, lokalizovane "-upraveno" ...) a video Live Photo (IMG_1234.MP4 / .MOV vedle
    // IMG_1234.HEIC). Pouziji se jen existujici soubory bez vlastniho JSON.
    private static readonly string[] EditedSuffixes = new string[] {
        "-edited", "-upraveno", "-upraven\u00e9", "-bearbeitet", "-modifi\u00e9", "-editado", "-modificato", "-bewerkt", "-edytowane", "-redigerad", "-muokattu" };
    public static List<string> GoogleJsonCompanions(string photoPath)
    {
        var list = new List<string>();
        try
        {
            string dir = Path.GetDirectoryName(photoPath);
            string bn = Path.GetFileNameWithoutExtension(photoPath);
            string ext = Path.GetExtension(photoPath);
            var cands = new List<string>();
            foreach (string suf in EditedSuffixes)
            {
                cands.Add(Path.Combine(dir, bn + suf + ext));
                if (!ext.Equals(".jpg", StringComparison.OrdinalIgnoreCase))
                    cands.Add(Path.Combine(dir, bn + suf + ".jpg"));   // upravena HEIC se uklada jako JPG
            }
            string el = ext.ToLowerInvariant();
            if (el == ".heic" || el == ".heif" || el == ".jpg" || el == ".jpeg")
            {
                cands.Add(Path.Combine(dir, bn + ".mp4"));
                cands.Add(Path.Combine(dir, bn + ".mov"));
            }
            foreach (string c in cands)
            {
                if (!File.Exists(c)) continue;
                if (File.Exists(c + ".json") || File.Exists(c + ".supplemental-metadata.json")) continue;
                bool dup = false;
                foreach (string x in list) if (string.Equals(x, c, StringComparison.OrdinalIgnoreCase)) dup = true;
                if (!dup) list.Add(c);
            }
        }
        catch {}
        return list;
    }

    public static PhotoRecordItem ProcessGoogleJson(string jsonPath, string rootBase, out string photoPathOut)
    {
        photoPathOut = null;
        try
        {
            string content = File.ReadAllText(jsonPath);
            if (!content.Contains("\"latitude\"") || !content.Contains("\"longitude\"")) return null;

            var matchTitle = Regex.Match(content, "\"title\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)+)\"");
            string title = matchTitle.Success ? JsonUnescape(matchTitle.Groups[1].Value) : Path.GetFileNameWithoutExtension(jsonPath);
            if (title.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0)
                title = Path.GetFileNameWithoutExtension(jsonPath);   // neplatny nazev (napr. s "/") - nepouzit

            // Souradnice + vyska z prvniho NENULOVEHO bloku geoData / geoDataExif (v poradi v souboru).
            // Google vyplnuje nezname misto nulami - kdyz je geoData 0,0 a geoDataExif ma skutecnou
            // polohu (nebo naopak), pouzije se ten platny blok. Vyska se bere vzdy ze stejneho bloku.
            double lat = 0, lon = 0;
            double? jsonAltitude = null;
            bool gotCoords = false;
            foreach (Match geoObj in Regex.Matches(content, @"""geoData(?:Exif)?""\s*:\s*\{[^}]*\}"))
            {
                string geoText = geoObj.Value;
                var mGeoLat = Regex.Match(geoText, @"""latitude""\s*:\s*([-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?)");
                var mGeoLon = Regex.Match(geoText, @"""longitude""\s*:\s*([-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?)");
                if (!mGeoLat.Success || !mGeoLon.Success) continue;
                double gLat = double.Parse(mGeoLat.Groups[1].Value, NumberStyles.Float, CultureInfo.InvariantCulture);
                double gLon = double.Parse(mGeoLon.Groups[1].Value, NumberStyles.Float, CultureInfo.InvariantCulture);
                if (Math.Abs(gLat) < 0.0001 && Math.Abs(gLon) < 0.0001) continue;
                if (Math.Abs(gLat) > 90.0 || Math.Abs(gLon) > 180.0) continue;
                lat = gLat; lon = gLon; gotCoords = true;
                var mGeoAlt = Regex.Match(geoText, @"""altitude""\s*:\s*([-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?)");
                if (mGeoAlt.Success)
                    jsonAltitude = PhotoRecordItem.ValidAltitude(double.Parse(mGeoAlt.Groups[1].Value, NumberStyles.Float, CultureInfo.InvariantCulture));
                break;
            }

            // JSON jineho tvaru (bez geoData bloku) - prvni dvojice latitude/longitude v souboru
            if (!gotCoords)
            {
                var matchLat = Regex.Match(content, @"""latitude""\s*:\s*([-+]?[0-9]*\.?[0-9]+)");
                var matchLon = Regex.Match(content, @"""longitude""\s*:\s*([-+]?[0-9]*\.?[0-9]+)");
                if (!matchLat.Success || !matchLon.Success) return null;
                lat = double.Parse(matchLat.Groups[1].Value, CultureInfo.InvariantCulture);
                lon = double.Parse(matchLon.Groups[1].Value, CultureInfo.InvariantCulture);
                if (Math.Abs(lat) < 0.0001 && Math.Abs(lon) < 0.0001) return null;
                if (Math.Abs(lat) > 90.0 || Math.Abs(lon) > 180.0) return null;
                var mAlt = Regex.Match(content, @"""altitude""\s*:\s*([-+]?[0-9]*\.?[0-9]+)");
                if (mAlt.Success)
                    jsonAltitude = PhotoRecordItem.ValidAltitude(double.Parse(mAlt.Groups[1].Value, CultureInfo.InvariantCulture));
            }

            string dateStr = "00000000_000000";
            int dateQuality = 0;
            // Jen photoTakenTime. Dalsi "timestamp" v souboru patri k creationTime / photoLastModifiedTime
            // (datum nahrani / upravy, ne porizeni) - bez photoTakenTime se pouzije datum ze samotne fotky.
            var matchTime = Regex.Match(content, @"""photoTakenTime""\s*:\s*\{[^}]*""timestamp""\s*:\s*""?([0-9]{9,18})""?");
            long epoch = 0;
            if (matchTime.Success && long.TryParse(matchTime.Groups[1].Value, out epoch))
            {
                // Google Takeout pouziva sekundy, milisekundy i mikrosekundy - normalizace na sekundy
                string rawTs = matchTime.Groups[1].Value;
                if (rawTs.Length >= 16) epoch /= 1000000;
                else if (rawTs.Length >= 13) epoch /= 1000;
                var dt = DateTimeOffset.FromUnixTimeSeconds(epoch).LocalDateTime;
                dateStr = dt.ToString("yyyyMMdd_HHmmss", CultureInfo.InvariantCulture);
                dateQuality = 1;   // UTC prevedeny na pasmo PC - vlastni EXIF fotky ma prednost
            }

            // Parovani s fotkou: nejdriv nazev odvozeny ze samotneho JSON souboru (presnejsi - u kopii
            // "IMG.jpg(1).json" je v "title" nazev originalu, ale patri ke kopii "IMG(1).jpg"),
            // az potom pole "title" (to nemusi odpovidat - prejmenovani, zkraceni nazvu Takeoutem)
            string photoPath = Path.Combine(Path.GetDirectoryName(jsonPath), title);
            foreach (string cand in GoogleJsonPhotoCandidates(jsonPath))
            {
                if (File.Exists(cand)) { photoPath = cand; title = Path.GetFileName(cand); break; }
            }
            long fSize = 0;
            string relPath = "";
            if (File.Exists(photoPath))
            {
                var fi = new FileInfo(photoPath);
                fSize = fi.Length;
                relPath = RelPath(photoPath, rootBase);
                photoPathOut = photoPath;
            }
            else
            {
                relPath = RelPath(jsonPath, rootBase);
            }

            return new PhotoRecordItem
            {
                FileName = title,
                DateTakenStr = dateStr,
                DateQuality = dateQuality,
                Latitude = Math.Round(lat, 6),
                Longitude = Math.Round(lon, 6),
                Altitude = jsonAltitude,
                FileSizeBytes = fSize,
                RelativePath = relPath,
                HasGps = true
            };
        }
        catch { return null; }
    }

    // Mozne nazvy fotky odvozene z nazvu Google Takeout JSON:
    //   IMG_1.jpg.json, IMG_1.jpg.supplemental-metadata.json, IMG_1.jpg.supplemental-meta.json (zkraceno),
    //   IMG_1.jpg(1).json -> IMG_1(1).jpg
    public static List<string> GoogleJsonPhotoCandidates(string jsonPath)
    {
        var list = new List<string>();
        string dir = Path.GetDirectoryName(jsonPath);
        string name = Path.GetFileNameWithoutExtension(jsonPath); // bez .json
        var names = new List<string>();
        names.Add(name);
        // odstranit (i zkraceny) priznak ".supplemental-metadata"
        int lastDot = name.LastIndexOf('.');
        if (lastDot > 0)
        {
            string seg = name.Substring(lastDot + 1).ToLowerInvariant();
            var segM = Regex.Match(seg, @"^(.*?)(\(\d+\))?$");
            string core = segM.Groups[1].Value;
            string copyNo = segM.Groups[2].Value; // napr. "(1)" u "IMG.jpg.supplemental-metadata(1).json"
            if (core.Length >= 2 && "supplemental-metadata".StartsWith(core, StringComparison.Ordinal))
                names.Add(name.Substring(0, lastDot) + copyNo);
        }
        // "IMG_1.jpg(1)" -> "IMG_1(1).jpg" (Takeout dava cislo kopie az za priponu)
        var extra = new List<string>();
        foreach (string nm in names)
        {
            var m = Regex.Match(nm, @"^(.+?)(\.[A-Za-z0-9]{2,5})\((\d+)\)$");
            if (m.Success) extra.Add(m.Groups[1].Value + "(" + m.Groups[3].Value + ")" + m.Groups[2].Value);
        }
        names.AddRange(extra);
        foreach (string nm in names)
        {
            if (string.IsNullOrEmpty(nm) || !IsValidMediaFile(nm)) continue;
            list.Add(Path.Combine(dir, nm));
        }
        return list;
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

            // exif:GPSLatitude / exif:GPSLongitude (Adobe) i drone-dji:GpsLatitude / GpsLongitude
            // (starsi DJI s preklepem "GpsLongtitude") - bez ohledu na velikost pismen
            var matchLat = Regex.Match(content, @"GPSLatitude(?!Ref)\s*(?:>|=\s*""|=\s*')\s*([^<""']+)", RegexOptions.IgnoreCase);
            var matchLon = Regex.Match(content, @"GPSLongt?itude(?!Ref)\s*(?:>|=\s*""|=\s*')\s*([^<""']+)", RegexOptions.IgnoreCase);
            double? lat = matchLat.Success ? ParseXmpCoordinate(matchLat.Groups[1].Value) : null;
            double? lon = matchLon.Success ? ParseXmpCoordinate(matchLon.Groups[1].Value) : null;

            // Souradnice muzou chybet - XMP sidecar pak muze mit aspon nadmorskou vysku
            bool hasLatLon = lat.HasValue && lon.HasValue;
            bool zeroCoord = hasLatLon && Math.Abs(lat.Value) < 0.0001 && Math.Abs(lon.Value) < 0.0001;
            bool outOfRange = hasLatLon && (Math.Abs(lat.Value) > 90.0 || Math.Abs(lon.Value) > 180.0);
            bool hasGps = hasLatLon && !zeroCoord && !outOfRange;

            string dateStr = "00000000_000000";
            int dateQuality = 0;
            // Poradi: exif:DateTimeOriginal, photoshop:DateCreated, xmp:CreateDate; hodnota s casem ma
            // prednost pred samotnym datem (photoshop:DateCreated byva jen "2023-10-15")
            string xmpDateVal = null;
            foreach (string dKey in new string[] { "DateTimeOriginal", "DateCreated", "CreateDate" })
            {
                foreach (Match md in Regex.Matches(content, @"(?<![A-Za-z])" + dKey + @"\s*(?:>|=\s*""|=\s*')\s*([^<""']+)"))
                {
                    string v = md.Groups[1].Value.Trim();
                    if (v.Length < 4) continue;
                    if (xmpDateVal == null) xmpDateVal = v;
                    if (v.IndexOf(':') > 0 && Regex.IsMatch(v, @"\d[T ]\d")) { xmpDateVal = v; goto xmpDateFound; }
                }
            }
            xmpDateFound:
            if (xmpDateVal != null)
            {
                dateStr = ParseDateTimeToFullStr(xmpDateVal, Path.GetFileName(xmpPath), File.GetLastWriteTime(xmpPath));
                dateQuality = 2;
            }

            // NADMORSKA_VYSKA z XMP: GPSAltitude a GPSAltitudeRef
            double? xmpAltitude = null;
            var matchAlt = Regex.Match(content, @"GPSAltitude(?!Ref)\s*(?:>|=\s*""|=\s*')\s*([^<""']+)", RegexOptions.IgnoreCase);
            var matchAltRef = Regex.Match(content, @"GPSAltitudeRef\s*(?:>|=\s*""|=\s*')\s*([^<""']+)", RegexOptions.IgnoreCase);
            if (matchAlt.Success)
            {
                double xmpAltVal;
                string xmpAltStr = matchAlt.Groups[1].Value.Trim();
                // XMP muze byt "375/100" (zlomek) nebo plain cislo
                int slash = xmpAltStr.IndexOf('/');
                if (slash > 0)
                {
                    double xmpNum, xmpDen;
                    if (double.TryParse(xmpAltStr.Substring(0, slash), NumberStyles.Any, CultureInfo.InvariantCulture, out xmpNum) &&
                        double.TryParse(xmpAltStr.Substring(slash + 1), NumberStyles.Any, CultureInfo.InvariantCulture, out xmpDen) &&
                        xmpDen != 0)
                    {
                        xmpAltVal = xmpNum / xmpDen;
                        string altRefStr = matchAltRef.Success ? matchAltRef.Groups[1].Value.Trim() : "0";
                        xmpAltitude = PhotoRecordItem.ValidAltitude((altRefStr == "1") ? -Math.Abs(xmpAltVal) : xmpAltVal);
                    }
                }
                else if (double.TryParse(xmpAltStr, NumberStyles.Any, CultureInfo.InvariantCulture, out xmpAltVal))
                {
                    string altRefStr = matchAltRef.Success ? matchAltRef.Groups[1].Value.Trim() : "0";
                    xmpAltitude = PhotoRecordItem.ValidAltitude((altRefStr == "1") ? -Math.Abs(xmpAltVal) : xmpAltVal);
                }
            }

            // Zaloha pro drony DJI: <drone-dji:AbsoluteAltitude>+0287.40</drone-dji:AbsoluteAltitude> (nad morem)
            if (!xmpAltitude.HasValue)
            {
                var matchAbsAlt = Regex.Match(content, @"AbsoluteAltitude(?:>|=""|=')\s*""?([+-]?\d+(?:\.\d+)?)");
                if (matchAbsAlt.Success)
                {
                    double absAlt;
                    if (double.TryParse(matchAbsAlt.Groups[1].Value, NumberStyles.Any, CultureInfo.InvariantCulture, out absAlt))
                        xmpAltitude = PhotoRecordItem.ValidAltitude(absAlt);
                }
            }

            // Bez platnych souradnic se XMP nepouzije - samotna vyska bez polohy nema vyznam a zahodi se
            if (!hasGps) return null;

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
                // RAW napred: Lightroom/Bridge zapisuji sidecar XMP prave k RAW (JPEG ma XMP uvnitr souboru),
                // u paru IMG.CR2 + IMG.JPG + IMG.xmp patri XMP k CR2
                string[] possibleExts = new string[] { ".dng", ".cr2", ".cr3", ".nef", ".arw", ".raf", ".orf", ".rw2", ".pef", ".srw",
                                                        ".jpg", ".jpeg", ".heic", ".heif", ".avif", ".tif", ".tiff", ".png", ".webp", ".bmp", ".gif",
                                                        ".mp4", ".mov", ".m4v", ".avi", ".mkv", ".wmv", ".3gp", ".mts", ".m2ts", ".mpg", ".mpeg" };
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
                DateQuality = dateQuality,
                Latitude = Math.Round(lat.Value, 6),
                Longitude = Math.Round(lon.Value, 6),
                Altitude = xmpAltitude,
                FileSizeBytes = fSize,
                RelativePath = relPath,
                HasGps = hasGps
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
        if (lowerName.StartsWith("._")) return true; // AppleDouble - macOS resource fork, neni skutecny obrazek
        return lowerName == "thumbs.db" || lowerName == "desktop.ini" || lowerName == ".ds_store" || lowerName == ".picasa.ini" || lowerName.EndsWith(".tmp");
    }

    private static bool IsJunkDirName(string lowerName)
    {
        foreach (string j in JunkDirNames) { if (lowerName == j) return true; }
        return false;
    }

    // Podpora cest delsich nez 260 znaku - pruchod adresari pres prefix \\?\
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
    private static PhotoRecordItem MakeRecord(string fileName, DateTime dateSource, double lat, double lon, long size, string rootBase, string actualPath, double? altitude = null)
    {
        return new PhotoRecordItem
        {
            FileName = fileName,
            DateTakenStr = ParseDateTimeToFullStr(null, fileName, dateSource),
            Latitude = lat,
            Longitude = lon,
            Altitude = altitude,
            FileSizeBytes = size,
            RelativePath = RelPath(actualPath, rootBase),
            HasGps = true
        };
    }

    // Slouceni zaznamu ze sidecar souboru (JSON/XMP/SRT) a videi:
    // - existuje-li uz zaznam G se stejnou relativni cestou, jen se doplni chybejici nadmorska vyska;
    // - je-li soubor zatim evidovan jako S (bez GNSS ve vlastnich metadatech), sidecar mu dodal
    //   souradnice -> zaznam S se odebere a nahradi zaznamem G (soubor nesmi byt ve vystupu 2x, G i S).
    //   Datum: vlastni metadata souboru maji prednost (EXIF pred Google JSON v UTC); sidecar vyhraje jen
    //   s duveryhodnejsim datem (DateQuality), napr. titulky DJI SRT pred casem mvhd videa.
    //   Vyska: vlastni vyska souboru (EXIF) ma prednost, sidecar ji jen doplni.
    private static void MergeSidecarRecord(ConcurrentDictionary<string, PhotoRecordItem> results,
        ConcurrentDictionary<string, PhotoRecordItem> noGpsResults, PhotoRecordItem r)
    {
        string key = r.RelativePath.ToLower();
        PhotoRecordItem existing;
        if (results.TryGetValue(key, out existing))
        {
            if (!existing.Altitude.HasValue && r.Altitude.HasValue) existing.Altitude = r.Altitude;
            return;
        }
        PhotoRecordItem sRec;
        if (noGpsResults.TryRemove(key, out sRec))
        {
            bool rNoDate = string.IsNullOrEmpty(r.DateTakenStr) || r.DateTakenStr.StartsWith("00000000", StringComparison.Ordinal);
            if (!string.IsNullOrEmpty(sRec.DateTakenStr) && (rNoDate || sRec.DateQuality >= r.DateQuality))
            {
                r.DateTakenStr = sRec.DateTakenStr;
                r.DateQuality = sRec.DateQuality;
            }
            if (sRec.Altitude.HasValue) r.Altitude = sRec.Altitude;
            if (r.FileSizeBytes == 0) r.FileSizeBytes = sRec.FileSizeBytes;
            // skutecny nazev a cesta souboru (sidecar je sestavuje s priponou malymi pismeny)
            r.FileName = sRec.FileName;
            r.RelativePath = sRec.RelativePath;
        }
        if (!results.TryAdd(key, r))
        {
            if (results.TryGetValue(key, out existing) && !existing.Altitude.HasValue && r.Altitude.HasValue)
                existing.Altitude = r.Altitude;
        }
    }

    // ------------------------------------------------------------------
    // GNSS z MP4/MOV videi (QuickTime atom udta/(c)xyz - telefony, drony, kamery)
    // ------------------------------------------------------------------
    // Obsah atomu moov (max 64 MB) z MP4/MOV/M4V/3GP. null = soubor moov nema (AVI, MKV, MTS, MPG ...)
    private static byte[] ReadMoov(string filePath)
    {
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
                    return br.ReadBytes(readLen);
                }
                pos += boxSize;
            }
        }
        return null;
    }

    // Vraci zaznam videa (s GNSS i bez nej - datum z metadat se pouzije i pro STAV=S),
    // null = video nema moov nebo nejde precist
    public static PhotoRecordItem ProcessVideoGps(string filePath, string rootBase)
    {
        try
        {
            var fi = new FileInfo(filePath);
            byte[] moov = ReadMoov(filePath);
            if (moov != null)
            {
                PhotoRecordItem rec = ExtractQuickTimeGps(moov, fi, rootBase);
                Interlocked.Increment(ref ReadOkCount);
                return rec;
            }
        }
        catch
        {
            Interlocked.Increment(ref ReadFailCount);
            FailByExt.AddOrUpdate(Path.GetExtension(filePath).ToLower(), 1, (k, v) => v + 1);
        }
        return null;
    }

    // ------------------------------------------------------------------
    // DATUM_CAS videa z metadat (MP4/MOV/M4V/3GP)
    //  1) iPhone: klic com.apple.quicktime.creationdate ("2023-08-01T18:30:00+0200") = mistni cas porizeni
    //  2) atom mvhd creation_time (sekundy od 1.1.1904, dle specifikace UTC) -> prevod na pasmo PC.
    //     Nektere kamery a drony (DJI, GoPro ...) ale zapisuji MISTNI cas misto UTC: pokud nazev souboru
    //     obsahuje datum+cas a shoduje se s neprevedenou hodnotou mvhd (do 5 min), pouzije se bez prevodu.
    //  Vraci "yyyyMMdd_HHmmss" nebo null (pak nazev souboru / datum zmeny).
    // ------------------------------------------------------------------
    private static DateTime? ReadMvhdRaw(byte[] moov)
    {
        for (int i = 4; i + 16 <= moov.Length; i++)
        {
            if (!TypeAt(moov, i, "mvhd")) continue;
            int boxSize = ReadBE32(moov, i - 4);
            if (boxSize < 20 || i - 4 + boxSize > moov.Length) continue;
            int ver = moov[i + 4];
            ulong secs = (ver == 1)
                ? (((ulong)(uint)ReadBE32(moov, i + 8)) << 32) | (uint)ReadBE32(moov, i + 12)
                : (uint)ReadBE32(moov, i + 8);
            if (secs == 0) return null;
            if (secs > 6000000000UL) return null; // nesmysl (po roce 2094)
            DateTime raw = new DateTime(1904, 1, 1, 0, 0, 0, DateTimeKind.Unspecified).AddSeconds(secs);
            if (raw.Year < 1990 || raw > DateTime.Now.AddDays(2)) return null;
            return raw;
        }
        return null;
    }

    public static string ReadVideoDate(byte[] moov, string fileName)
    {
        int q;
        return ReadVideoDate(moov, fileName, out q);
    }

    // quality: 2 = mistni cas (Apple creationdate, mvhd potvrzeny nazvem souboru), 1 = mvhd UTC -> pasmo PC
    public static string ReadVideoDate(byte[] moov, string fileName, out int quality)
    {
        quality = 0;
        string apple = null;
        try { apple = FindAppleKeyValue(moov, "com.apple.quicktime.creationdate"); } catch {}
        if (!string.IsNullOrEmpty(apple))
        {
            string r = ParseIsoWallClock(apple.Trim('\0', ' '));
            if (r != null) { quality = 2; return r; }
        }

        DateTime? raw = null;
        try { raw = ReadMvhdRaw(moov); } catch {}
        if (raw.HasValue)
        {
            DateTime? fn = ParseFileNameDateTime(Path.GetFileNameWithoutExtension(fileName));
            if (fn.HasValue && Math.Abs((fn.Value - raw.Value).TotalMinutes) <= 5)
            {
                quality = 2;
                return raw.Value.ToString("yyyyMMdd_HHmmss", CultureInfo.InvariantCulture);   // kamera zapsala mistni cas
            }
            DateTime local = DateTime.SpecifyKind(raw.Value, DateTimeKind.Utc).ToLocalTime();
            quality = 1;
            return local.ToString("yyyyMMdd_HHmmss", CultureInfo.InvariantCulture);
        }
        return null;
    }

    // Datum videa ze souboru (pro DJI SRT a statistiku). null = nelze urcit z metadat
    public static string GetVideoDateString(string videoPath)
    {
        int q;
        return GetVideoDateString(videoPath, out q);
    }

    public static string GetVideoDateString(string videoPath, out int quality)
    {
        quality = 0;
        try
        {
            byte[] moov = ReadMoov(videoPath);
            if (moov != null) return ReadVideoDate(moov, Path.GetFileName(videoPath), out quality);
        }
        catch {}
        return null;
    }

    // Poloha z ISO 6709 retezce "+50.1234+014.5678[+250.1]/" (lat, lon, volitelne vyska)
    private static readonly Regex Iso6709Regex = new Regex(@"([+-]\d{1,3}(?:\.\d+)?)([+-]\d{1,3}(?:\.\d+)?)([+-]\d{1,5}(?:\.\d+)?)?", RegexOptions.Compiled);
    private static bool TryParseIso6709(string s, out double lat, out double lon, out double? alt)
    {
        lat = 0; lon = 0; alt = null;
        if (string.IsNullOrEmpty(s)) return false;
        var m = Iso6709Regex.Match(s);
        if (!m.Success) return false;
        lat = double.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture);
        lon = double.Parse(m.Groups[2].Value, CultureInfo.InvariantCulture);
        if (Math.Abs(lat) > 90.0 || Math.Abs(lon) > 180.0) return false;
        if (Math.Abs(lat) < 0.0001 && Math.Abs(lon) < 0.0001) return false;
        alt = ParseIso6709Altitude(m.Groups[3]);
        return true;
    }

    private static int ReadBE32(byte[] b, int p)
    {
        return (b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3];
    }

    private static bool TypeAt(byte[] b, int p, string type)
    {
        if (p < 0 || p + 4 > b.Length) return false;
        for (int k = 0; k < 4; k++) if (b[p + k] != (byte)type[k]) return false;
        return true;
    }

    // Apple/iPhone: moov/meta/keys obsahuje klic "com.apple.quicktime.location.ISO6709",
    // hodnota je v moov/meta/ilst v polozce s typem = poradove cislo klice (1..n), atom 'data'.
    private static string FindAppleKeysLocation(byte[] moov)
    {
        return FindAppleKeyValue(moov, "com.apple.quicktime.location.ISO6709");
    }

    // Hodnota libovolneho klice z Apple moov/meta/keys + ilst (location.ISO6709, creationdate ...)
    private static string FindAppleKeyValue(byte[] moov, string wanted)
    {
        for (int i = 4; i + 12 <= moov.Length; i++)
        {
            if (!TypeAt(moov, i, "keys")) continue;
            int boxStart = i - 4;
            int boxSize = ReadBE32(moov, boxStart);
            if (boxSize < 16 || boxStart + boxSize > moov.Length) continue;
            int count = ReadBE32(moov, i + 8);
            if (count <= 0 || count > 10000) continue;
            int p = i + 12;
            int boxEnd = boxStart + boxSize;
            int wantedIndex = -1;
            for (int k = 1; k <= count && p + 8 <= boxEnd; k++)
            {
                int ks = ReadBE32(moov, p);
                if (ks < 8 || p + ks > boxEnd) break;
                string key = System.Text.Encoding.UTF8.GetString(moov, p + 8, ks - 8);
                if (key == wanted) { wantedIndex = k; break; }
                p += ks;
            }
            if (wantedIndex < 0) continue;

            // ilst za keys (ve stejnem meta atomu)
            for (int j = boxEnd + 4; j + 4 <= moov.Length; j++)
            {
                if (!TypeAt(moov, j, "ilst")) continue;
                int ilStart = j - 4;
                int ilSize = ReadBE32(moov, ilStart);
                if (ilSize < 8 || ilStart + ilSize > moov.Length) continue;
                int ilEnd = ilStart + ilSize;
                int q = j + 4;
                while (q + 8 <= ilEnd)
                {
                    int itSize = ReadBE32(moov, q);
                    if (itSize < 8 || q + itSize > ilEnd) break;
                    int itIndex = ReadBE32(moov, q + 4);
                    if (itIndex == wantedIndex)
                    {
                        int d = q + 8;
                        while (d + 16 <= q + itSize)
                        {
                            int dSize = ReadBE32(moov, d);
                            if (dSize < 16 || d + dSize > q + itSize) break;
                            if (TypeAt(moov, d + 4, "data"))
                                return System.Text.Encoding.UTF8.GetString(moov, d + 16, dSize - 16);
                            d += dSize;
                        }
                    }
                    q += itSize;
                }
                break;
            }
        }
        return null;
    }

    // 3GPP 'loci' atom (3GP/MP4 z nekterych telefonu a kamer): souradnice a vyska jako 16.16 fixed point
    private static bool TryParseLoci(byte[] moov, out double lat, out double lon, out double? alt)
    {
        lat = 0; lon = 0; alt = null;
        for (int i = 4; i + 4 <= moov.Length; i++)
        {
            if (!TypeAt(moov, i, "loci")) continue;
            int boxStart = i - 4;
            int boxSize = ReadBE32(moov, boxStart);
            if (boxSize < 8 + 4 + 2 + 1 + 1 + 12 || boxStart + boxSize > moov.Length) continue;
            int boxEnd = boxStart + boxSize;
            int p = i + 4 + 4 + 2;               // version/flags + language
            while (p < boxEnd && moov[p] != 0) p++; // name (UTF-8, ukoncen nulou)
            p++;                                 // nulovy bajt
            p++;                                 // role
            if (p + 12 > boxEnd) continue;
            double lo = ReadBE32(moov, p) / 65536.0;
            double la = ReadBE32(moov, p + 4) / 65536.0;
            double al = ReadBE32(moov, p + 8) / 65536.0;
            if (Math.Abs(la) > 90.0 || Math.Abs(lo) > 180.0) continue;
            if (Math.Abs(la) < 0.0001 && Math.Abs(lo) < 0.0001) continue;
            lat = la; lon = lo; alt = PhotoRecordItem.ValidAltitude(al);
            return true;
        }
        return false;
    }

    // Poloha videa ze vsech znamych mist v moov atomu:
    //   1) udta/(c)xyz (Android, starsi iPhone, kamery)  2) Apple keys location.ISO6709 (iPhone MOV)
    //   3) 3GPP loci. Prvni nalezene souradnice vyhravaji; chybi-li u nich vyska, doplni se
    //   z jineho zdroje, ktery ukazuje na stejne misto.
    private static PhotoRecordItem ExtractQuickTimeGps(byte[] moov, FileInfo fi, string rootBase)
    {
        var cands = new List<double[]>(); // [lat, lon, alt nebo NaN]

        for (int i = 0; i <= moov.Length - 4; i++)
        {
            if (moov[i] == 0xA9 && moov[i + 1] == 0x78 && moov[i + 2] == 0x79 && moov[i + 3] == 0x7A)
            {
                int take = Math.Min(160, moov.Length - (i + 4));
                if (take <= 0) continue;
                string ascii = System.Text.Encoding.ASCII.GetString(moov, i + 4, take);
                double la, lo; double? al;
                if (TryParseIso6709(ascii, out la, out lo, out al))
                {
                    cands.Add(new double[] { la, lo, al.HasValue ? al.Value : double.NaN });
                    break;
                }
            }
        }

        string appleLoc = null;
        try { appleLoc = FindAppleKeysLocation(moov); } catch {}
        {
            double la, lo; double? al;
            if (TryParseIso6709(appleLoc, out la, out lo, out al))
                cands.Add(new double[] { la, lo, al.HasValue ? al.Value : double.NaN });
        }

        try
        {
            double la, lo; double? al;
            if (TryParseLoci(moov, out la, out lo, out al))
                cands.Add(new double[] { la, lo, al.HasValue ? al.Value : double.NaN });
        }
        catch {}

        int vQuality;
        string vDate = ReadVideoDate(moov, fi.Name, out vQuality);
        if (cands.Count == 0)
        {
            // video bez GNSS - vratit zaznam pro STAV=S s datem z metadat
            return new PhotoRecordItem
            {
                FileName = fi.Name,
                FileSizeBytes = fi.Length,
                RelativePath = RelPath(fi.FullName, rootBase),
                DateTakenStr = vDate ?? ParseDateTimeToFullStr(null, fi.Name, fi.LastWriteTime),
                DateQuality = vDate != null ? vQuality : 0,
                HasGps = false
            };
        }
        double[] best = cands[0];
        double? alt = double.IsNaN(best[2]) ? (double?)null : best[2];
        if (!alt.HasValue)
        {
            foreach (var c in cands)
            {
                if (double.IsNaN(c[2])) continue;
                if (Math.Abs(c[0] - best[0]) < 0.001 && Math.Abs(c[1] - best[1]) < 0.001) { alt = c[2]; break; }
            }
        }
        var vrec = MakeRecord(fi.Name, fi.LastWriteTime, Math.Round(best[0], 6), Math.Round(best[1], 6), fi.Length, rootBase, fi.FullName, alt);
        if (vDate != null) { vrec.DateTakenStr = vDate; vrec.DateQuality = vQuality; }
        return vrec;
    }

    // Volitelna 3. slozka ISO 6709 zapisu souradnic = nadmorska vyska v metrech
    private static double? ParseIso6709Altitude(Group g)
    {
        if (g == null || !g.Success || string.IsNullOrEmpty(g.Value)) return null;
        double a;
        if (double.TryParse(g.Value, NumberStyles.Any, CultureInfo.InvariantCulture, out a))
        {
            return PhotoRecordItem.ValidAltitude(a);
        }
        return null;
    }

    // ------------------------------------------------------------------
    // GNSS z DJI .srt titulku - format GPS(lon,lat[,alt]) dle specifikace DJI
    // ------------------------------------------------------------------
    public static PhotoRecordItem ProcessSrtFile(string srtPath, string rootBase)
    {
        try
        {
            string content = File.ReadAllText(srtPath);
            double lat = 0, lon = 0;
            double? altitude = null;
            bool found = false;

            // DJI zapisuje polohu do kazdeho snimku titulku. Na zacatku zaznamu (pred ziskanim GNSS fixu)
            // byva 0,0 - proto se projdou snimky postupne a pouzije se prvni s platnymi souradnicemi.
            // Nadmorska vyska se bere ze stejneho snimku, pripadne z prvniho dalsiho snimku, ktery ji ma.
            var reLat  = new Regex(@"(?<![A-Za-z_])(?:latitude|lat)\s*[:=]\s*([+-]?\d+(?:\.\d+)?)", RegexOptions.IgnoreCase);
            var reLon  = new Regex(@"(?<![A-Za-z_])(?:longt?itude|lon|long|lng)\s*[:=]\s*([+-]?\d+(?:\.\d+)?)", RegexOptions.IgnoreCase);
            var reGps  = new Regex(@"GPS\s*[(:]\s*([+-]?\d+(?:\.\d+)?)\s*,\s*([+-]?\d+(?:\.\d+)?)");
            // NADMORSKA_VYSKA: jen absolutni vyska nad morem (abs_alt / absoluteAltitude).
            // Relativni udaje (rel_alt, height, relativeAltitude) ani 3. hodnota GPS(...) u starsich DJI
            // modelu se nepouzivaji - mohou byt vztazeny ke vzletisti, ne k hladine more.
            var reAlt  = new Regex(@"(?<![A-Za-z_])(?:abs_alt|absoluteAltitude)\s*[:=]\s*([+-]?\d+(?:\.\d+)?)", RegexOptions.IgnoreCase);

            string[] blocks = Regex.Split(content, @"\r?\n[ \t]*\r?\n");
            for (int bi = 0; bi < blocks.Length; bi++)
            {
                string blk = blocks[bi];
                double bLat = 0, bLon = 0;
                bool bOk = false;
                var mLat = reLat.Match(blk);
                var mLon = reLon.Match(blk);
                if (mLat.Success && mLon.Success)
                {
                    bLat = double.Parse(mLat.Groups[1].Value, CultureInfo.InvariantCulture);
                    bLon = double.Parse(mLon.Groups[1].Value, CultureInfo.InvariantCulture);
                    bOk = true;
                }
                else
                {
                    var m = reGps.Match(blk);
                    if (m.Success)
                    {
                        double v1 = double.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture);
                        double v2 = double.Parse(m.Groups[2].Value, CultureInfo.InvariantCulture);
                        // DJI specifikace: GPS(delka, sirka, vyska) -> v1 = lon, v2 = lat
                        bLon = v1; bLat = v2;
                        // Pokud je druha hodnota mimo rozsah sirky a prvni je v nem, bylo to GPS(lat, lon)
                        if (Math.Abs(bLat) > 90.0 && Math.Abs(bLon) <= 90.0) { bLat = v1; bLon = v2; }
                        bOk = true;
                    }
                }
                if (!bOk) continue;
                if (Math.Abs(bLat) > 90.0 || Math.Abs(bLon) > 180.0) continue;
                if (Math.Abs(bLat) < 0.0001 && Math.Abs(bLon) < 0.0001) continue;

                lat = bLat; lon = bLon; found = true;
                for (int ai = bi; ai < blocks.Length && !altitude.HasValue; ai++)
                {
                    var mAlt = reAlt.Match(blocks[ai]);
                    double altVal;
                    if (mAlt.Success && double.TryParse(mAlt.Groups[1].Value, NumberStyles.Any, CultureInfo.InvariantCulture, out altVal))
                        altitude = PhotoRecordItem.ValidAltitude(altVal);
                }
                break;
            }
            if (!found) return null;

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

            var srec = MakeRecord(title, File.GetLastWriteTime(actual), Math.Round(lat, 6), Math.Round(lon, 6), fSize, rootBase, actual, altitude);
            // DATUM_CAS: DJI zapisuje do titulku mistni cas snimku ("2023-10-15 14:30:22.123",
            // starsi modely "2017.08.05 14:11:51"); jinak datum z metadat paroveho videa
            string srtDate = null;
            int srtQuality = 2;
            var mSrtDate = Regex.Match(content, @"(?<!\d)((?:19|20)\d\d)[-./](\d{2})[-./](\d{2})[ T]+(\d{2}):(\d{2}):(\d{2})");
            if (mSrtDate.Success)
                srtDate = ParseIsoWallClock(string.Format("{0}-{1}-{2}T{3}:{4}:{5}", mSrtDate.Groups[1].Value, mSrtDate.Groups[2].Value,
                    mSrtDate.Groups[3].Value, mSrtDate.Groups[4].Value, mSrtDate.Groups[5].Value, mSrtDate.Groups[6].Value));
            if (srtDate == null && !actual.Equals(srtPath, StringComparison.OrdinalIgnoreCase))
                srtDate = GetVideoDateString(actual, out srtQuality);
            if (srtDate != null) { srec.DateTakenStr = srtDate; srec.DateQuality = srtQuality; }
            return srec;
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
                    string fullName = f.FullName; // s \\?\ prefixem kvuli dlouhym cestam - oreze az RelPath()
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
                EnumErrors++; // neprojitelna slozka - pristup odmitnut, dlouha cesta apod.
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
                    // S: fotka bez GNSS - evidovat pro STAV=S (varianta A: kopie = 2x S, pocty sedi)
                    noGpsResults.TryAdd(key, r);
                }
            });

            // Videa pred sidecar soubory (JSON/XMP/SRT): video bez GNSS musi byt v evidenci S drive, nez mu
            // sidecar doda souradnice - jinak by bylo ve vystupu dvakrat (G ze sidecaru i S z videa)
            if (videoFiles.Count > 0)
            {
                Parallel.ForEach(videoFiles, opts, v =>
                {
                    var r = ProcessVideoGps(v, rootBase);
                    Interlocked.Increment(ref _progressProcessed);
                    if (r != null && r.HasGps)
                    {
                        MergeSidecarRecord(results, noGpsResults, r);
                    }
                    else
                    {
                        // S: video bez GNSS - vyrobit zaznam bez souradnic pro STAV=S
                        try
                        {
                            var fiV = new FileInfo(v);
                            string relV = RelPath(v, rootBase);
                            var recS = new PhotoRecordItem
                            {
                                FileName = fiV.Name,
                                FileSizeBytes = fiV.Length,
                                RelativePath = relV,
                                // datum z metadat videa (mvhd / Apple creationdate), jinak nazev / datum zmeny
                                DateTakenStr = (r != null && !string.IsNullOrEmpty(r.DateTakenStr))
                                    ? r.DateTakenStr
                                    : ParseDateTimeToFullStr(null, fiV.Name, fiV.LastWriteTime),
                                DateQuality = (r != null && !string.IsNullOrEmpty(r.DateTakenStr)) ? r.DateQuality : 0,
                                HasGps = false
                            };
                            noGpsResults.TryAdd(relV.ToLower(), recS);
                        }
                        catch {}
                    }
                });
            }

            if (jsonFiles.Count > 0)
            {
                Parallel.ForEach(jsonFiles, opts, j =>
                {
                    string jPhoto;
                    var r = ProcessGoogleJson(j, rootBase, out jPhoto);
                    if (r != null && r.HasGps)
                    {
                        // upravena kopie a video Live Photo dostanou polohu ze stejneho JSON (pred hlavnim
                        // zaznamem - MergeSidecarRecord muze r upravit)
                        if (jPhoto != null)
                        {
                            foreach (string comp in GoogleJsonCompanions(jPhoto))
                            {
                                try
                                {
                                    var cfi = new FileInfo(comp);
                                    var cr = new PhotoRecordItem
                                    {
                                        FileName = cfi.Name,
                                        DateTakenStr = r.DateTakenStr,
                                        DateQuality = r.DateQuality,
                                        Latitude = r.Latitude,
                                        Longitude = r.Longitude,
                                        Altitude = r.Altitude,
                                        FileSizeBytes = cfi.Length,
                                        RelativePath = RelPath(comp, rootBase),
                                        HasGps = true
                                    };
                                    MergeSidecarRecord(results, noGpsResults, cr);
                                }
                                catch {}
                            }
                        }
                        MergeSidecarRecord(results, noGpsResults, r);
                    }
                });
            }

            if (xmpFiles.Count > 0)
            {
                Parallel.ForEach(xmpFiles, opts, x =>
                {
                    var r = ProcessXmpFile(x, rootBase);
                    if (r == null) return;
                    if (r.HasGps)
                    {
                        MergeSidecarRecord(results, noGpsResults, r);
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
                        MergeSidecarRecord(results, noGpsResults, r);
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

        // Seradit dle DATUM_CAS (vzestupne), pri shode dle NAZEV_SOUBORU, pak dle RELATIVNI_CESTA
        // (deterministicky - u shodnych kopii v ruznych slozkach dostane G vzdy abecedne prvni cesta)
        list.Sort((a, b) =>
        {
            int cmp = string.Compare(a.DateTakenStr, b.DateTakenStr, StringComparison.Ordinal);
            if (cmp != 0) return cmp;
            cmp = string.Compare(a.FileName, b.FileName, StringComparison.OrdinalIgnoreCase);
            if (cmp != 0) return cmp;
            // shodne datum i nazev (kopie v jine slozce): rozhodne abecedne prvni relativni cesta
            return string.Compare(a.RelativePath ?? "", b.RelativePath ?? "", StringComparison.OrdinalIgnoreCase);
        });

        long beforeDedup = list.Count;

        // Deduplikace ve dvou urovnich (jen zaznamy s GNSS):
        // 1) Identicke zaznamy (DATUM_CAS + NAZEV + LAT + LON) - prvni G, dalsi D
        // 2) Stejny soubor (nazev bez pripony) na stejnem miste - sloucit, i kdyz se datum lisi
        //    (typicky EXIF vs. doplnek z Google JSON/XMP sidecar souboru) - ponechany G, vyrazeny D
        // Bez GNSS (S) se nededuplikuje - varianta A: kopie ve 2 slozkach = 2x S, aby sedely pocty.
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
                    // nahradit zaznam bez data zaznamem se skutecnym datem - puvodni se stava duplicitou D
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

        // Dosledne doplneni nadmorske vysky: duplicite D ji muzou mit vyplnenou, ale zachovany
        // zaznam G ne (typicky EXIF fotka bez vysky + Google JSON/XMP sidecar s vyskou) - prenest.
        // Resi se az po deduplikaci, aby vyska dosla ke skutecne zachovanemu zaznamu.
        foreach (var r in dupList)
        {
            if (!r.Altitude.HasValue) continue;
            string posKey = Path.GetFileNameWithoutExtension(r.FileName).ToLowerInvariant() + "|"
                          + r.Latitude.ToString("F4", CultureInfo.InvariantCulture) + "|"
                          + r.Longitude.ToString("F4", CultureInfo.InvariantCulture);
            PhotoRecordItem kept;
            if (byFilePos.TryGetValue(posKey, out kept) && !kept.Altitude.HasValue)
                kept.Altitude = r.Altitude;
        }

        var deduped = new List<PhotoRecordItem>(byFilePos.Values);
        foreach (var g in deduped) { g.Status = "G"; }
        foreach (var d in dupList) { if (string.IsNullOrEmpty(d.Status)) d.Status = "D"; }
        deduped.Sort((a, b) =>
        {
            int cmp = string.Compare(a.DateTakenStr, b.DateTakenStr, StringComparison.Ordinal);
            if (cmp != 0) return cmp;
            cmp = string.Compare(a.FileName, b.FileName, StringComparison.OrdinalIgnoreCase);
            if (cmp != 0) return cmp;
            // shodne datum i nazev (kopie v jine slozce): rozhodne abecedne prvni relativni cesta
            return string.Compare(a.RelativePath ?? "", b.RelativePath ?? "", StringComparison.OrdinalIgnoreCase);
        });
        dupList.Sort((a, b) =>
        {
            int cmp = string.Compare(a.DateTakenStr, b.DateTakenStr, StringComparison.Ordinal);
            if (cmp != 0) return cmp;
            cmp = string.Compare(a.FileName, b.FileName, StringComparison.OrdinalIgnoreCase);
            if (cmp != 0) return cmp;
            // shodne datum i nazev (kopie v jine slozce): rozhodne abecedne prvni relativni cesta
            return string.Compare(a.RelativePath ?? "", b.RelativePath ?? "", StringComparison.OrdinalIgnoreCase);
        });

        var noGpsList = new List<PhotoRecordItem>(noGpsResults.Values);
        foreach (var s in noGpsList) { s.Status = "S"; s.Altitude = null; } // vyska jen u zaznamu s polohou
        noGpsList.Sort((a, b) =>
        {
            int cmp = string.Compare(a.DateTakenStr, b.DateTakenStr, StringComparison.Ordinal);
            if (cmp != 0) return cmp;
            cmp = string.Compare(a.FileName, b.FileName, StringComparison.OrdinalIgnoreCase);
            if (cmp != 0) return cmp;
            // shodne datum i nazev (kopie v jine slozce): rozhodne abecedne prvni relativni cesta
            return string.Compare(a.RelativePath ?? "", b.RelativePath ?? "", StringComparison.OrdinalIgnoreCase);
        });

        var allRecs = new List<PhotoRecordItem>(deduped.Count + dupList.Count + noGpsList.Count);
        allRecs.AddRange(deduped);
        allRecs.AddRange(dupList);
        allRecs.AddRange(noGpsList);
        allRecs.Sort((a, b) =>
        {
            int cmp = string.Compare(a.DateTakenStr, b.DateTakenStr, StringComparison.Ordinal);
            if (cmp != 0) return cmp;
            cmp = string.Compare(a.FileName, b.FileName, StringComparison.OrdinalIgnoreCase);
            if (cmp != 0) return cmp;
            // shodne datum i nazev (kopie v jine slozce): rozhodne abecedne prvni relativni cesta
            return string.Compare(a.RelativePath ?? "", b.RelativePath ?? "", StringComparison.OrdinalIgnoreCase);
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
                            string dt = ReadPhotoDate(metadata);
                            if (dt != null) return dt;
                            return ParseDateTimeToFullStr(null, fileName, lastWriteTime);
                        }
                    }
                }
            }
            catch {}
        }
        else if (IsVideoFile(fileName))
        {
            string vd = GetVideoDateString(filePath);
            if (vd != null) return vd;
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
                try { Console.Write("\r   {0}: {1}/{2} {3} ({4:F1} %) - {5:N0} {6}    ", label, fld, totalFolders, unitFld, pct, fil, unitFil); } catch {}
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
                    Console.WriteLine("\r   {0}: {1}/{2} {3} (100,0 %) - {4:N0} {5}    ", label, fld, totalFolders, unitFld, fil, unitFil);
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
        # Prvni spusteni: 3 s timeout, pak auto-1
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
        # Dalsi spusteni: cekat neomezene na jednu klavesu (bez Enteru)
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
            Write-Host "      - Reads GNSS from EXIF/XMP metadata of photos, videos (MP4, MOV, M4V, 3GP),"
            Write-Host "        Google Photos JSON, Adobe XMP and DJI SRT drone subtitle files."
            Write-Host "      - Pairs sidecar files: XMP belongs to RAW (when RAW and JPG share a name), Google JSON"
            Write-Host "        applies also to the edited copy (-edited) and to the Live Photo video."
            Write-Host "      - Reads also altitude (GPSAltitude) from the same sources when recorded (G and D only)."
            Write-Host "        Altitude exactly 0 (= not measured) or outside -500..15000 m is discarded (left empty)."
            Write-Host "      - Deduplicates GNSS records (first G, rest D): identical records and files with the same"
            Write-Host "        name (no extension) at the same place, e.g. Live Photo video next to HEIC, JPG next to RAW."
            Write-Host "      - Sorts all records chronologically."
            Write-Host "      - Contains ALL files: G=unique with GNSS (map), S=without GNSS, D=GNSS duplicates."
            Write-Host "      - Output file  : " -NoNewline; Write-Host "Mapa_Fotek_data_YYYYMMDD.txt" -ForegroundColor Cyan
            Write-Host "      - Output format: JavaScript data file (window.MAPA_FOTEK_DATA)"
            Write-Host "        Columns (semicolon-separated): DATE_TIME; NAME; LAT; LON; BYTES; PATH; STATUS; ALTITUDE"
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
            Write-Host "        Oldest/newest is determined by date taken (same rules as option [1])."
            Write-Host "      - Output file  : " -NoNewline; Write-Host "Mapa_Fotek_statistika_YYYYMMDD.csv" -ForegroundColor Cyan
            Write-Host "      - Output format: Tabular CSV file (UTF-8 with BOM for Excel)"
            Write-Host "        Table 1: Detailed statistics for all individual subfolders"
            Write-Host "        Table 2: Aggregated summary of 1st-level main folders"
            Write-Host ""
            Write-Host " DATE AND TIME (DATE_TIME column):" -ForegroundColor Yellow
            Write-Host "  - Photos: date taken from EXIF/XMP (local time as recorded by the camera)."
            Write-Host "  - Videos: date stored in the video (iPhone incl. time zone, others converted from UTC"
            Write-Host "    to the PC time zone); DJI drones: time from the SRT subtitles."
            Write-Host "  - The file's own metadata take precedence over Google JSON (UTC converted to PC time zone)."
            Write-Host "  - Fallback: date in the file name (e.g. IMG_20231015_143022), then file modification date."
            Write-Host "    Camera counters in names (IMG_2034, DSC_1999 ...) are not treated as a year."
            Write-Host ""
            Write-Host " SUPPORTED FORMATS:" -ForegroundColor Yellow
            Write-Host "  - Photos : JPG, JPEG, HEIC, HEIF, AVIF, PNG, TIF, TIFF, BMP, GIF, WEBP"
            Write-Host "  - RAW    : DNG, CR2, CR3, NEF, ARW, RAF, ORF, RW2, PEF, SRW"
            Write-Host "  - Videos : MP4, MOV, M4V, AVI, MKV, WMV, 3GP, FLV, MTS, M2TS, MPG, MPEG"
            Write-Host "             (GNSS and date only from MP4, MOV, M4V, 3GP; other formats get GNSS only"
            Write-Host "              from JSON/XMP/SRT and the date from the file name / modification date)"
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
            Write-Host "      - Nacte GNSS z EXIF/XMP metadat fotek, z videi (MP4, MOV, M4V, 3GP),"
            Write-Host "        z Google Photos JSON, Adobe XMP a DJI SRT titulku k videim."
            Write-Host "      - Paruje doprovodne soubory: XMP patri k RAW (maji-li RAW a JPG stejny nazev), Google JSON"
            Write-Host "        plati i pro upravenou kopii (-edited) a pro video Live Photo."
            Write-Host "      - Nacte i nadmorskou vysku (GPSAltitude) ze stejnych zdroju, pokud je zaznamenana (jen G a D)."
            Write-Host "        Vyska presne 0 (= nezmereno) nebo mimo -500 az 15000 m se zahodi (pole zustane prazdne)."
            Write-Host "      - Deduplikuje zaznamy s GNSS (prvni G, dalsi D): shodne zaznamy a soubory se stejnym nazvem"
            Write-Host "        (bez pripony) na stejnem miste, napr. video Live Photo vedle HEIC nebo JPG vedle RAW."
            Write-Host "      - Vsechny zaznamy seradi podle data."
            Write-Host "      - Obsahuje VSECHNY soubory: G=unikat s GNSS (mapa), S=bez GNSS, D=duplicita s GNSS."
            Write-Host "      - Vystupni soubor: " -NoNewline; Write-Host "Mapa_Fotek_data_YYYYMMDD.txt" -ForegroundColor Cyan
            Write-Host "      - Format vystupu : JavaScriptovy datovy soubor (window.MAPA_FOTEK_DATA)"
            Write-Host "        Sloupce oddelene strednikem: DATUM_CAS; NAZEV; LAT; LON; BAJTY; CESTA; STAV; NADMORSKA_VYSKA"
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
            Write-Host "        Nejstarsi/nejnovejsi se urcuje podle data porizeni (stejna pravidla jako volba [1])."
            Write-Host "      - Vystupni soubor: " -NoNewline; Write-Host "Mapa_Fotek_statistika_YYYYMMDD.csv" -ForegroundColor Cyan
            Write-Host "      - Format vystupu : Tabulkovy CSV soubor (UTF-8 s BOM pro Excel)"
            Write-Host "        Tabulka 1: Detailni prehled vsech jednotlivych podslozek"
            Write-Host "        Tabulka 2: Souhrn hlavnich slozek 1. urovne vcetne jejich podslozek"
            Write-Host ""
            Write-Host " DATUM A CAS (sloupec DATUM_CAS):" -ForegroundColor Yellow
            Write-Host "  - Fotky: datum porizeni z EXIF/XMP (mistni cas tak, jak ho zapsal fotoaparat)."
            Write-Host "  - Videa: datum ulozene ve videu (iPhone vcetne casoveho pasma, ostatni prevedeno z UTC"
            Write-Host "    na casove pasmo PC); drony DJI: cas z titulku SRT."
            Write-Host "  - Vlastni metadata souboru maji prednost pred Google JSON (UTC prevedeny na pasmo PC)."
            Write-Host "  - Nahradne: datum v nazvu souboru (napr. IMG_20231015_143022), pak datum zmeny souboru."
            Write-Host "    Cisla snimku v nazvu (IMG_2034, DSC_1999 ...) se za rok nepovazuji."
            Write-Host ""
            Write-Host " PODPOROVANE FORMATY:" -ForegroundColor Yellow
            Write-Host "  - Fotky  : JPG, JPEG, HEIC, HEIF, AVIF, PNG, TIF, TIFF, BMP, GIF, WEBP"
            Write-Host "  - RAW    : DNG, CR2, CR3, NEF, ARW, RAF, ORF, RW2, PEF, SRW"
            Write-Host "  - Videa  : MP4, MOV, M4V, AVI, MKV, WMV, 3GP, FLV, MTS, M2TS, MPG, MPEG"
            Write-Host "             (GNSS a datum jen z MP4, MOV, M4V, 3GP; ostatni formaty ziskaji GNSS jen"
            Write-Host "              z JSON/XMP/SRT a datum z nazvu souboru / data zmeny)"
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
            if ($isEn) { Write-Host " Returning to main menu..." -ForegroundColor Yellow }
            else { Write-Host " Navrat do hlavni nabidky..." -ForegroundColor Yellow }
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

        $todayStr = (Get-Date).ToString("yyyyMMdd", [System.Globalization.CultureInfo]::InvariantCulture)
        $timestampHeader = (Get-Date).ToString("dd.MM.yyyy HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
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
        Write-Host "[1/3] Scanning folders (ALL files incl. without GNSS), loading EXIF, videos, Google JSON, Adobe XMP, DJI SRT..." -ForegroundColor Yellow
    } else {
        Write-Host " Slozka fotek: $targetDir" -ForegroundColor White
        Write-Host " Rezim       : POUZE PRO CTENI (zadne fotky se nemeni)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "[1/3] Skenuji slozky (VSECHNY soubory vcetne bez GNSS), nacitam EXIF, videa, Google JSON, Adobe XMP, DJI SRT..." -ForegroundColor Yellow
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

    # Pocet zaznamu s vyplnenou nadmorskou vyskou (8. sloupec)
    $altCount = 0
    foreach ($rec in $allRecords) { if ($null -ne $rec.Altitude) { $altCount++ } }

    if ($isEn) {
        Write-Host ("   Total files in folders     : {0:N0}" -f $totalCount) -ForegroundColor Green
        Write-Host ("   Files with GNSS (incl. D)  : {0:N0}" -f $gpsBeforeDedup) -ForegroundColor Green
        Write-Host ("   Unique for map (G)         : {0:N0}  (duplicates D: {1:N0}, without GNSS S: {2:N0})" -f $gpsRecords.Count, $dupRecords.Count, $noGpsRecords.Count) -ForegroundColor Green
        Write-Host ("   With altitude              : {0:N0}" -f $altCount) -ForegroundColor Green
        Write-Host ("   Total file size            : {0}  (scan time: {1:N1} s)" -f $formattedTotalBytes, $sw.Elapsed.TotalSeconds) -ForegroundColor Green
    } else {
        Write-Host ("   Celkem souboru ve slozkach : {0:N0}" -f $totalCount) -ForegroundColor Green
        Write-Host ("   Souboru s GNSS (vc. D)     : {0:N0}" -f $gpsBeforeDedup) -ForegroundColor Green
        Write-Host ("   Unikatnich pro mapu (G)    : {0:N0}  (duplicity D: {1:N0}, bez GNSS S: {2:N0})" -f $gpsRecords.Count, $dupRecords.Count, $noGpsRecords.Count) -ForegroundColor Green
        Write-Host ("   S nadmorskou vyskou        : {0:N0}" -f $altCount) -ForegroundColor Green
        Write-Host ("   Celkovy objem souboru      : {0}  (cas skenu: {1:N1} s)" -f $formattedTotalBytes, $sw.Elapsed.TotalSeconds) -ForegroundColor Green
    }

    # Souhrn necitelnych souboru (napr. HEIC bez nainstalovaneho kodeku)
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
                Write-Host ("   Neprojitelne slozky        : {0:N0}  (pristup odmitnut / prilis dlouha cesta)" -f $enumErrors) -ForegroundColor DarkYellow
            }
        }
    }

    $todayStr = (Get-Date).ToString("yyyyMMdd", [System.Globalization.CultureInfo]::InvariantCulture)
    $timestampHeader = (Get-Date).ToString("dd.MM.yyyy HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
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
    $sb.AppendLine("// Sloupce: DATUM_CAS; `t NAZEV_SOUBORU; `t LATITUDE; `t LONGITUDE; `t VELIKOST_BAJTY; `t RELATIVNI_CESTA; `t STAV (G=GNSS unikat, S=bez GNSS, D=duplicita s GNSS); `t NADMORSKA_VYSKA") | Out-Null
    $sb.AppendLine("window.MAPA_FOTEK_DATA = " + $bt) | Out-Null
    $sb.AppendLine("DATUM_CAS;" + $tab + "NAZEV_SOUBORU;" + $tab + "LATITUDE;" + $tab + "LONGITUDE;" + $tab + "VELIKOST_BAJTY;" + $tab + "RELATIVNI_CESTA;" + $tab + "STAV;" + $tab + "NADMORSKA_VYSKA") | Out-Null

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
        $altStr = if ($null -ne $item.Altitude) { $item.Altitude.ToString("F1", $nfi) } else { "" }
        $line = "{0};{1}{2};{1}{3};{1}{4};{1}{5};{1}{6};{1}{7};{1}{8}" -f $item.DateTakenStr, $tab, $item.FileName, $latStr, $lonStr, $item.FileSizeBytes, $item.RelativePath, $st, $altStr
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
        Write-Host (" Files with GNSS     : {0:N0}  (incl. duplicates)" -f $gpsBeforeDedup) -ForegroundColor White
        Write-Host (" Unique for map (G)  : {0:N0}  (D duplicates: {1:N0}, S without GNSS: {2:N0})" -f $gpsRecords.Count, $dupRecords.Count, $noGpsRecords.Count) -ForegroundColor White
        Write-Host (" Rows in output file : {0:N0}" -f $allRecords.Count) -ForegroundColor White
        Write-Host (" With altitude       : {0:N0}" -f $altCount) -ForegroundColor White
        Write-Host ""
        Write-Host (" Total data volume   : {0}" -f $formattedTotalBytes) -ForegroundColor White
        Write-Host " Output file         : $outFileName" -ForegroundColor White
        if ($readFailCount -gt 0) {
            Write-Host (" Failed to read      : {0:N0}  (missing codec or damaged file)" -f $readFailCount) -ForegroundColor Yellow
        }
    } else {
        Write-Host " AKTUALIZACE DOKONCENA USPESNE!" -ForegroundColor Green
        Write-Host " Cas vygenerovani           : $timestampHeader" -ForegroundColor White
        Write-Host ""
        Write-Host (" Celkem souboru             : {0:N0}" -f $totalCount) -ForegroundColor White
        Write-Host (" Souboru s GNSS             : {0:N0}  (vcetne duplicit)" -f $gpsBeforeDedup) -ForegroundColor White
        Write-Host (" Unikatnich pro mapu (G)    : {0:N0}  (D duplicit: {1:N0}, S bez GNSS: {2:N0})" -f $gpsRecords.Count, $dupRecords.Count, $noGpsRecords.Count) -ForegroundColor White
        Write-Host (" Radku ve vystupnim souboru : {0:N0}" -f $allRecords.Count) -ForegroundColor White
        Write-Host (" S nadmorskou vyskou        : {0:N0}" -f $altCount) -ForegroundColor White
        Write-Host ""
        Write-Host (" Celkovy datovy objem       : {0}" -f $formattedTotalBytes) -ForegroundColor White
        Write-Host " Vystupni soubor            : $outFileName" -ForegroundColor White
        if ($readFailCount -gt 0) {
            Write-Host (" Nepodarilo se precist      : {0:N0}  (viz souhrn vyse - chybi kodek nebo poskozeny soubor)" -f $readFailCount) -ForegroundColor Yellow
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
