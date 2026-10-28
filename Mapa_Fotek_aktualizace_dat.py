#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Mapa Fotek - Aktualizace dat
Autor: Jan BARTUNEK
Verze: 2.21 (25.10.2026)
Multiplatformní verze (Windows, Linux, macOS, Android/Termux)

Logika generování datového TXT je sjednocena s referenční verzí
Mapa_Fotek_aktualizace_dat.bat (PowerShell + C#): stejné filtry souborů,
stejné pořadí zdrojů data a polohy, stejné párování sidecar souborů
(Google JSON, XMP, DJI SRT), stejné slučování a deduplikace a stejný
formát výstupu (UTF-8 s BOM, CRLF, čísla formátovaná jako .NET Framework).
Rozdíl zůstává jen tam, kde BAT závisí na kodecích Windows (WIC):
Python čte EXIF/XMP vlastními parsery, nezávisle na nainstalovaných kodecích.
"""

import os
import sys
import re
import math
import time
import struct
import zlib
import datetime
from datetime import timezone
from decimal import Decimal, ROUND_HALF_UP
from concurrent.futures import ThreadPoolExecutor

# Volitelná podpora Pillow - jen poslední záloha, když vlastní parsery nic nenajdou
try:
    from PIL import Image, ExifTags
    HAS_PILLOW = True
except ImportError:
    HAS_PILLOW = False

SCRIPT_VERSION = "2.21"
SCRIPT_DATE = "25.10.2026"

# Podporované přípony souborů (shodné s BAT: ValidMediaExtensions / VideoExtensions)
PHOTO_EXTS = {
    ".jpg", ".jpeg", ".heic", ".heif", ".avif", ".png", ".tif", ".tiff", ".bmp", ".gif", ".webp",
    ".dng", ".cr2", ".cr3", ".nef", ".arw", ".raf", ".orf", ".rw2", ".pef", ".srw"
}
VIDEO_EXTS = {
    ".mp4", ".mov", ".m4v", ".avi", ".mkv", ".wmv", ".3gp", ".flv", ".mts", ".m2ts", ".mpg", ".mpeg"
}
MEDIA_EXTS = PHOTO_EXTS | VIDEO_EXTS

# Filtr odpadních souborů a složek - shodný s BAT (IsJunkFileName / JunkDirNames)
JUNK_FILE_NAMES = {"thumbs.db", "desktop.ini", ".ds_store", ".picasa.ini"}
JUNK_DIR_NAMES = {
    "@eadir", ".@__thumb", ".thumbnails", "$recycle.bin", "system volume information",
    "__macosx", ".trashes", ".trash"
}

DATE_ZERO = "00000000_000000"


# ==============================================================================
# POMOCNÉ FUNKCE (chování jako .NET Framework)
# ==============================================================================
def round_net(val, digits):
    """Math.Round(double, int) z .NET Framework (bankéřské zaokrouhlení po vynásobení)."""
    if val is None:
        return None
    factor = 10.0 ** digits
    return round(val * factor) / factor


def fmt_net(val, digits):
    """
    double.ToString("F<digits>", InvariantCulture) z .NET Framework (Windows PowerShell 5.1):
    nejdřív 15 platných číslic, pak zaokrouhlení půlky směrem od nuly; záporná nula bez znaménka.
    """
    if val is None:
        return ""
    d = Decimal("%.15g" % val).quantize(Decimal(1).scaleb(-digits), rounding=ROUND_HALF_UP)
    out = format(d, "f")
    if out.startswith("-") and not out.strip("-0."):
        out = out[1:]
    return out


def net_ext(name):
    """Path.GetExtension: od poslední tečky (tečka na konci = bez přípony)."""
    i = name.rfind(".")
    if i < 0 or i == len(name) - 1:
        return ""
    return name[i:]


def net_name_wo_ext(name):
    """Path.GetFileNameWithoutExtension."""
    i = name.rfind(".")
    return name if i < 0 else name[:i]


def _ord_ic_key(s):
    """Klíč pro StringComparison.OrdinalIgnoreCase (velká písmena znak po znaku, pořadí UTF-16)."""
    s = s or ""
    up = "".join(c.upper() if len(c.upper()) == 1 else c for c in s)
    return up.encode("utf-16-be", "surrogatepass")


def read_text_net(path):
    """File.ReadAllText: rozpozná BOM (UTF-8 / UTF-16), jinak UTF-8."""
    with open(path, "rb") as f:
        raw = f.read()
    if raw.startswith(b"\xef\xbb\xbf"):
        return raw[3:].decode("utf-8", errors="replace")
    if raw.startswith(b"\xff\xfe"):
        return raw[2:].decode("utf-16-le", errors="replace")
    if raw.startswith(b"\xfe\xff"):
        return raw[2:].decode("utf-16-be", errors="replace")
    return raw.decode("utf-8", errors="replace")


def file_mtime_dt(path):
    """FileInfo.LastWriteTime (místní čas)."""
    try:
        return datetime.datetime.fromtimestamp(os.stat(path).st_mtime)
    except Exception:
        return datetime.datetime(1601, 1, 1)


class _DirIndex:
    """
    Vyhledání souboru bez ohledu na velikost písmen (jako File.Exists ve Windows) i na Linuxu/Androidu.
    Vrací skutečnou cestu souboru nebo None.
    """
    def __init__(self):
        self._cache = {}

    def find(self, path):
        d, n = os.path.split(path)
        idx = self._cache.get(d)
        if idx is None:
            idx = {}
            try:
                with os.scandir(d) as it:
                    for e in it:
                        try:
                            if e.is_file():
                                idx.setdefault(e.name.lower(), e.name)
                        except OSError:
                            pass
            except OSError:
                pass
            self._cache[d] = idx
        real = idx.get(n.lower())
        return os.path.join(d, real) if real is not None else None

    def exists(self, path):
        return self.find(path) is not None


# ==============================================================================
# TŘÍDA PRO ZÁZNAM MÉDIA
# ==============================================================================
class PhotoRecordItem:
    ALT_MIN = -500.0
    ALT_MAX = 15000.0

    def __init__(self, file_name="", date_taken_str="",
                 latitude=0.0, longitude=0.0, altitude=None,
                 relative_path="", file_size_bytes=0, has_gps=False,
                 status="", date_quality=0):
        self.file_name = file_name
        self.date_taken_str = date_taken_str
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude  # float nebo None
        self.relative_path = relative_path
        self.file_size_bytes = file_size_bytes
        self.has_gps = has_gps
        self.status = status      # "G", "D", "S"
        # 0 = náhradní (název / datum změny), 1 = UTC převedený na pásmo PC, 2 = místní čas pořízení
        self.date_quality = date_quality

    @staticmethod
    def valid_altitude(raw):
        if raw is None:
            return None
        try:
            val = float(raw)
        except (ValueError, TypeError):
            return None
        if math.isnan(val) or math.isinf(val):
            return None
        if val == 0.0:
            return None
        if val < PhotoRecordItem.ALT_MIN or val > PhotoRecordItem.ALT_MAX:
            return None
        return round_net(val, 1)


# ==============================================================================
# FILTROVÁNÍ SOUBORŮ (shodné s BAT)
# ==============================================================================
def is_own_output_file(name_lower):
    if name_lower.startswith("mapa_fotek"):
        return True
    if name_lower.startswith("statistika_"):
        return True
    if name_lower.endswith((".bat", ".ps1", ".cmd", ".py")):
        return True
    if name_lower.endswith((".html", ".htm")):
        return True
    if name_lower in ("souradnice_fotek.txt", "statistika_fotky.csv"):
        return True
    return False


def is_junk_file_name(name_lower):
    if name_lower.startswith("._"):  # AppleDouble - resource fork z macOS, není to obrázek
        return True
    return name_lower in JUNK_FILE_NAMES or name_lower.endswith(".tmp")


def is_junk_dir_name(dir_lower):
    return dir_lower in JUNK_DIR_NAMES


def is_valid_media_file(name):
    ext = net_ext(name).lower()
    return bool(ext) and ext in MEDIA_EXTS


def is_video_file(name):
    ext = net_ext(name).lower()
    return bool(ext) and ext in VIDEO_EXTS


# ==============================================================================
# DATUM Z NÁZVU SOUBORU (shodné s BAT)
# ==============================================================================
FN_DATETIME_REGEX = re.compile(r'(?<!\d)(19\d\d|20\d\d)[-_.]?(0[1-9]|1[0-2])[-_.]?(0[1-9]|[12]\d|3[01])[ _\-T.]?([01]\d|2[0-3])[-_.:]?([0-5]\d)[-_.:]?([0-5]\d)(?:\d{1,3})?(?!\d)')
FN_DATE_REGEX = re.compile(r'(?<!\d)(19\d\d|20\d\d)([-_.]?)(0[1-9]|1[0-2])\2(0[1-9]|[12]\d|3[01])(?!\d)')
FN_YEAR_MONTH_REGEX = re.compile(r'(?<![A-Za-z0-9])(19\d\d|20\d\d)[-_.](0[1-9]|1[0-2])(?!\d)')
FN_YEAR_REGEX = re.compile(r'(?<![A-Za-z0-9])(19\d\d|20\d\d)(?!\d)')
FN_COUNTER_REGEX = re.compile(r'(?<![A-Za-z0-9])(?:IMG|IMGP|DSC|DSCN|DSCF|DSCI|_DSC|DSC_|_MG|MVI|VID|MOV|MAH|PICT|PIC|CIMG|IMAG|HPIM|SAM|SDIM|DCP|DCIM|KIF|CRW|GOPR|GP|DJI|PANO|P|R|WP|CAM|SNC|EX|MG)[_\- ]?(\d{4})(?!\d)', re.IGNORECASE)


def fn_year_ok(y_str):
    try:
        v = int(y_str)
        return 1900 <= v <= datetime.datetime.now().year + 1
    except Exception:
        return False


def parse_filename_datetime_only(name):
    """ParseFileNameDateTime: jen plné datum + čas z názvu (bez přípony), jinak None."""
    for m in FN_DATETIME_REGEX.finditer(name):
        if not fn_year_ok(m.group(1)):
            continue
        try:
            return datetime.datetime(int(m.group(1)), int(m.group(2)), int(m.group(3)),
                                     int(m.group(4)), int(m.group(5)), int(m.group(6)))
        except ValueError:
            pass
    return None


def parse_filename_date(filename):
    """ParseFileNameDate: datum+čas, datum, rok-měsíc, rok (ne počitadla fotoaparátů)."""
    if not filename:
        return None
    name = net_name_wo_ext(filename)

    full = parse_filename_datetime_only(name)
    if full:
        return full.strftime("%Y%m%d_%H%M%S")

    for m in FN_DATE_REGEX.finditer(name):
        if not fn_year_ok(m.group(1)):
            continue
        try:
            dt = datetime.datetime(int(m.group(1)), int(m.group(3)), int(m.group(4)))
            return dt.strftime("%Y%m%d") + "_000000"
        except ValueError:
            pass

    counter_pos = {cm.start(1) for cm in FN_COUNTER_REGEX.finditer(name)}

    for m in FN_YEAR_MONTH_REGEX.finditer(name):
        if m.start() in counter_pos or not fn_year_ok(m.group(1)):
            continue
        return f"{m.group(1)}{m.group(2)}01_000000"

    for m in FN_YEAR_REGEX.finditer(name):
        if m.start() in counter_pos or not fn_year_ok(m.group(1)):
            continue
        return f"{m.group(1)}0101_000000"

    return None


# ==============================================================================
# PARSOVÁNÍ DATA (shodné s BAT: ParseIsoWallClock, DateFormats, ParseDateTimeToFullStr)
# ==============================================================================
def is_valid_year(year):
    return 1900 <= year <= 2100


ISO_DATE_REGEX = re.compile(
    r'^(\d{4})[-:](\d{2})[-:](\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:[.,]\d+)?)?\s*(Z|[+-]\d{2}(?::?\d{2})?)?$',
    re.IGNORECASE
)


def _utc_to_local(dt):
    return dt.replace(tzinfo=timezone.utc).astimezone().replace(tzinfo=None)


def parse_iso_wall_clock(s):
    """ISO 8601 -> 'yyyyMMdd_HHmmss'. Číselné pásmo = místní čas (bez převodu), 'Z' = převod na pásmo PC."""
    if not s or not isinstance(s, str):
        return None
    m = ISO_DATE_REGEX.match(s)
    if not m:
        return None
    try:
        sec = int(m.group(6)) if m.group(6) else 0
        dt = datetime.datetime(int(m.group(1)), int(m.group(2)), int(m.group(3)),
                               int(m.group(4)), int(m.group(5)), sec)
        if m.group(7) and m.group(7).upper() == "Z":
            dt = _utc_to_local(dt)
        if not is_valid_year(dt.year):
            return None
        return dt.strftime("%Y%m%d_%H%M%S")
    except Exception:
        return None


# Přesné formáty v pořadí jako v BAT (DateFormats). Den-první má přednost před americkým zápisem.
# (formát, má_pásmo)
DATE_FORMATS = (
    ("%Y:%m:%d %H:%M:%S", False),
    ("%Y-%m-%d %H:%M:%S", False),
    ("%Y/%m/%d %H:%M:%S", False),
    ("%Y-%m-%dT%H:%M:%S", False),
    ("%Y-%m-%dT%H:%M:%S%z", True),     # yyyy-MM-ddTHH:mm:ssK / zzz
    ("%Y-%m-%d %H:%M:%S%z", True),     # yyyy-MM-dd HH:mm:sszzz
    ("%d.%m.%Y %H:%M:%S", False),      # dd.MM.yyyy HH:mm:ss + d.M.yyyy H:mm:ss
    ("%d.%m.%Y %H:%M", False),
    ("%d.%m.%Y", False),
    ("%Y:%m:%d %H:%M", False),
    ("%Y-%m-%d %H:%M", False),
    ("%Y-%m-%d", False),
    ("%Y/%m/%d", False),
    ("%Y%m%d_%H%M%S", False),
    ("%Y%m%d-%H%M%S", False),
    ("%Y%m%dT%H%M%S", False),
    ("%Y%m%d", False),
    ("%d/%m/%Y %H:%M:%S", False),
    ("%d/%m/%Y %H:%M", False),
    ("%d/%m/%Y", False),
    ("%m/%d/%Y %H:%M:%S", False),
    ("%m/%d/%Y", False),
)

# Náhrada obecného DateTime.TryParse (cs-CZ, pak invariantní kultura) - nejčastější další zápisy
LENIENT_FORMATS = (
    ("%d. %m. %Y %H:%M:%S", False),
    ("%d. %m. %Y %H:%M", False),
    ("%d. %m. %Y", False),
    ("%d.%m.%Y %H:%M:%S.%f", False),
    ("%Y-%m-%dT%H:%M:%S.%f", False),
    ("%Y-%m-%d %H:%M:%S.%f", False),
    ("%Y-%m-%dT%H:%M:%S.%f%z", True),
    ("%Y-%m-%dT%H:%M", False),
    ("%Y-%m-%dT%H:%M%z", True),
    ("%m/%d/%Y %I:%M:%S %p", False),
    ("%m/%d/%Y %I:%M %p", False),
)


def _try_formats(s, formats):
    for fmt, has_tz in formats:
        try:
            dt = datetime.datetime.strptime(s, fmt)
        except Exception:
            continue
        try:
            if has_tz and dt.tzinfo is not None:
                # .NET (DateTimeStyles.None) převede čas s pásmem na místní čas PC
                dt = dt.astimezone().replace(tzinfo=None)
        except Exception:
            continue
        if is_valid_year(dt.year):
            return dt
    return None


def try_parse_known_formats(s):
    return _try_formats(s, DATE_FORMATS)


def parse_date_to_full_str(date_taken, file_name, file_date):
    """ParseDateTimeToFullStr: text data -> název souboru -> datum změny (datetime)."""
    if date_taken is not None and str(date_taken).strip():
        s = str(date_taken).strip()
        iso = parse_iso_wall_clock(s)
        if iso:
            return iso
        dt = try_parse_known_formats(s)
        if dt:
            return dt.strftime("%Y%m%d_%H%M%S")
        s2 = re.sub(r"\s+", " ", s)
        dt = _try_formats(s2, LENIENT_FORMATS) or (try_parse_known_formats(s2) if s2 != s else None)
        if dt:
            return dt.strftime("%Y%m%d_%H%M%S")

    from_name = parse_filename_date(file_name)
    if from_name:
        return from_name

    if isinstance(file_date, datetime.datetime):
        return file_date.strftime("%Y%m%d_%H%M%S")
    return DATE_ZERO


def try_raw_exif_date(s):
    """TryRawExifDate: surový EXIF řetězec -> 'yyyyMMdd_HHmmss' nebo None."""
    if not isinstance(s, str):
        return None
    s = s.strip("\0 ")
    if len(s) < 10 or s.startswith("0000"):
        return None
    dt = try_parse_known_formats(s)
    if dt:
        return dt.strftime("%Y%m%d_%H%M%S")
    if len(s) > 19:
        dt = try_parse_known_formats(s[:19])
        if dt:
            return dt.strftime("%Y%m%d_%H%M%S")
    return None


# ==============================================================================
# EXIF / TIFF PARSER (čistý Python - JPEG, TIFF, DNG, RAW, PNG, WebP, HEIC/AVIF, CR3)
# ==============================================================================
class _Src:
    """Zdroj bajtů: buffer v paměti, případně dočítání ze souboru (velké RAW)."""
    def __init__(self, data, f=None, base=0):
        self.data = data
        self.f = f
        self.base = base  # pozice začátku TIFF v souboru (pro dočítání)

    def get(self, off, n):
        if off < 0 or n <= 0:
            return b""
        if off + n <= len(self.data):
            return self.data[off:off + n]
        if self.f is not None:
            try:
                self.f.seek(self.base + off)
                return self.f.read(n)
            except Exception:
                return b""
        return self.data[off:off + n]


_TIFF_TYPE_SIZE = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8}
_TIFF_MAGICS = (42, 0x4F52, 0x5352, 0x55)  # TIFF, ORF (RO / SR), RW2


def _tiff_header(src):
    h = src.get(0, 8)
    if len(h) < 8:
        return None, None
    if h[:2] == b"II":
        e = "<"
    elif h[:2] == b"MM":
        e = ">"
    else:
        return None, None
    if struct.unpack(e + "H", h[2:4])[0] not in _TIFF_MAGICS:
        return None, None
    return e, struct.unpack(e + "I", h[4:8])[0]


def _read_ifd(src, e, off):
    entries = {}
    cnt_b = src.get(off, 2)
    if len(cnt_b) < 2:
        return entries
    n = struct.unpack(e + "H", cnt_b)[0]
    if n == 0 or n > 1000:
        return entries
    blk = src.get(off + 2, n * 12)
    for i in range(len(blk) // 12):
        tag, typ, count = struct.unpack(e + "HHI", blk[i * 12:i * 12 + 8])
        raw4 = blk[i * 12 + 8:i * 12 + 12]
        entries[tag] = (typ, count, raw4)
    return entries


def _tag_value(src, e, entry):
    typ, count, raw4 = entry
    size = _TIFF_TYPE_SIZE.get(typ)
    if size is None or count == 0 or count > 1000000:
        return None
    total = size * count
    if total <= 4:
        data = raw4[:total]
    else:
        data = src.get(struct.unpack(e + "I", raw4)[0], total)
        if len(data) < total:
            return None
    if typ == 2:
        return data.decode("utf-8", errors="replace").split("\0")[0]
    if typ in (1, 7):
        return list(data)
    if typ == 6:
        return list(struct.unpack(e + "%db" % count, data))
    if typ == 3:
        return list(struct.unpack(e + "%dH" % count, data))
    if typ == 8:
        return list(struct.unpack(e + "%dh" % count, data))
    if typ == 4:
        return list(struct.unpack(e + "%dI" % count, data))
    if typ == 9:
        return list(struct.unpack(e + "%di" % count, data))
    if typ in (5, 10):
        fmt = "II" if typ == 5 else "ii"
        return [struct.unpack(e + fmt, data[i * 8:i * 8 + 8]) for i in range(count)]
    if typ == 11:
        return list(struct.unpack(e + "%df" % count, data))
    if typ == 12:
        return list(struct.unpack(e + "%dd" % count, data))
    return None


def _rat(v):
    """DecodeRational: jmenovatel 0 -> 0."""
    if isinstance(v, tuple):
        return 0.0 if v[1] == 0 else float(v[0]) / float(v[1])
    return float(v)


def _gps_to_decimal(vals, ref):
    """ConvertGpsToDecimal: 1-3 hodnoty (stupně, minuty, sekundy), ref začíná S/W = záporné."""
    if not vals:
        return None
    try:
        deg = _rat(vals[0])
        mi = _rat(vals[1]) if len(vals) > 1 else 0.0
        se = _rat(vals[2]) if len(vals) > 2 else 0.0
    except Exception:
        return None
    dec = deg + mi / 60.0 + se / 3600.0
    if isinstance(ref, str) and ref[:1].upper() in ("S", "W"):
        dec = -dec
    return dec


def _new_meta():
    return {"date_orig": None, "date_dig": None, "gps": None, "alt_raw": None,
            "alt_ref": 0, "xmp": None, "found": False}


def _parse_tiff_into(src, meta):
    """Přečte IFD0 + Exif SubIFD + GPS IFD jednoho TIFF bloku a doplní chybějící údaje do meta."""
    e, ifd0_off = _tiff_header(src)
    if e is None:
        return False
    ifd0 = _read_ifd(src, e, ifd0_off)
    if not ifd0:
        return False
    meta["found"] = True

    # Exif SubIFD (nebo "plochý" blok s Exif tagy přímo v IFD0 - CR3 CMT2)
    exif_ifd = None
    if 0x8769 in ifd0:
        v = _tag_value(src, e, ifd0[0x8769])
        if v:
            exif_ifd = _read_ifd(src, e, v[0])
    elif 0x9003 in ifd0 or 0x9004 in ifd0:
        exif_ifd = ifd0
    if exif_ifd:
        if meta["date_orig"] is None and 0x9003 in exif_ifd:
            meta["date_orig"] = try_raw_exif_date(_tag_value(src, e, exif_ifd[0x9003]))
        if meta["date_dig"] is None and 0x9004 in exif_ifd:
            meta["date_dig"] = try_raw_exif_date(_tag_value(src, e, exif_ifd[0x9004]))

    # GPS IFD (nebo "plochý" GPS blok - CR3 CMT4)
    gps_ifd = None
    if 0x8825 in ifd0:
        v = _tag_value(src, e, ifd0[0x8825])
        if v:
            gps_ifd = _read_ifd(src, e, v[0])
    elif 2 in ifd0 and 4 in ifd0 and ifd0[2][0] in (5, 10):
        gps_ifd = ifd0
    if gps_ifd:
        if meta["gps"] is None and 2 in gps_ifd and 4 in gps_ifd:
            la = _gps_to_decimal(_tag_value(src, e, gps_ifd[2]), _tag_value(src, e, gps_ifd[1]) if 1 in gps_ifd else None)
            lo = _gps_to_decimal(_tag_value(src, e, gps_ifd[4]), _tag_value(src, e, gps_ifd[3]) if 3 in gps_ifd else None)
            if la is not None and lo is not None:
                meta["gps"] = (la, lo)
        if meta["alt_raw"] is None and 6 in gps_ifd:
            v = _tag_value(src, e, gps_ifd[6])
            try:
                raw = _rat(v[0]) if v else None
            except Exception:
                raw = None
            if raw is not None:
                ref = 0
                if 5 in gps_ifd:
                    rv = _tag_value(src, e, gps_ifd[5])
                    if isinstance(rv, list) and rv:
                        ref = 1 if rv[0] == 1 else 0
                    elif isinstance(rv, str):
                        ref = 1 if rv.strip() == "1" else 0
                meta["alt_raw"] = raw
                meta["alt_ref"] = ref

    # XMP v TIFF/DNG/RAW (tag 700)
    if meta["xmp"] is None and 700 in ifd0:
        v = _tag_value(src, e, ifd0[700])
        if isinstance(v, list):
            meta["xmp"] = bytes(v).decode("utf-8", errors="replace")
        elif isinstance(v, str):
            meta["xmp"] = v
    return True


def _parse_jpeg_bytes(data, meta):
    if data[:2] != b"\xff\xd8":
        return False
    meta["found"] = True
    p = 2
    n = len(data)
    while p + 4 <= n:
        if data[p] != 0xFF:
            break
        marker = data[p + 1]
        if marker == 0xFF:          # výplňový bajt
            p += 1
            continue
        if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
            p += 2
            continue
        if marker in (0xDA, 0xD9):  # SOS / EOI
            break
        length = struct.unpack(">H", data[p + 2:p + 4])[0]
        if length < 2:
            break
        seg = data[p + 4:p + 2 + length]
        if marker == 0xE1:
            if seg.startswith(b"Exif\x00\x00"):
                _parse_tiff_into(_Src(seg[6:]), meta)
            elif seg.startswith(b"http://ns.adobe.com/xap/1.0/\x00") and meta["xmp"] is None:
                meta["xmp"] = seg[29:].decode("utf-8", errors="replace")
        p += 2 + length
    return True


def _read_jpeg_head(f):
    """Načte JPEG až po začátek obrazových dat (SOS) - metadata jsou vždy před ním."""
    out = bytearray(f.read(2))
    if bytes(out) != b"\xff\xd8":
        return bytes(out)
    while True:
        h = f.read(4)
        if len(h) < 4:
            break
        out += h
        if h[0] != 0xFF:
            break
        marker = h[1]
        if marker in (0xDA, 0xD9):
            break
        if marker == 0xFF:              # výplňový bajt - posun o 1
            f.seek(-3, os.SEEK_CUR)
            del out[-3:]
            continue
        if marker == 0x01 or 0xD0 <= marker <= 0xD7:   # samostatné značky bez délky
            f.seek(-2, os.SEEK_CUR)
            del out[-2:]
            continue
        length = struct.unpack(">H", h[2:4])[0]
        if length < 2:
            break
        out += f.read(length - 2)
        if len(out) > 64 * 1024 * 1024:
            break
    return bytes(out)


def _parse_png(f, meta):
    if f.read(8) != b"\x89PNG\r\n\x1a\n":
        return False
    meta["found"] = True
    while True:
        hdr = f.read(8)
        if len(hdr) < 8:
            break
        length, ctype = struct.unpack(">I4s", hdr)
        if ctype in (b"IDAT", b"IEND"):
            if ctype == b"IEND":
                break
            f.seek(length + 4, os.SEEK_CUR)
            continue
        data = f.read(length)
        f.read(4)  # CRC
        if ctype == b"eXIf":
            _parse_tiff_into(_Src(data[6:] if data.startswith(b"Exif\x00\x00") else data), meta)
        elif ctype == b"iTXt" and data.startswith(b"XML:com.adobe.xmp\x00") and meta["xmp"] is None:
            rest = data[len(b"XML:com.adobe.xmp\x00"):]
            if len(rest) >= 2:
                comp_flag = rest[0]
                rest = rest[2:]
                parts = rest.split(b"\x00", 2)   # jazyk, přeložené klíčové slovo, text
                if len(parts) == 3:
                    txt = parts[2]
                    if comp_flag == 1:
                        try:
                            txt = zlib.decompress(txt)
                        except Exception:
                            txt = b""
                    meta["xmp"] = txt.decode("utf-8", errors="replace")
    return True


def _parse_webp(f, meta):
    h = f.read(12)
    if len(h) < 12 or h[:4] != b"RIFF" or h[8:12] != b"WEBP":
        return False
    meta["found"] = True
    while True:
        ch = f.read(8)
        if len(ch) < 8:
            break
        ctype = ch[:4]
        size = struct.unpack("<I", ch[4:8])[0]
        if ctype in (b"EXIF", b"XMP "):
            data = f.read(size)
            if ctype == b"EXIF":
                _parse_tiff_into(_Src(data[6:] if data.startswith(b"Exif\x00\x00") else data), meta)
            elif meta["xmp"] is None:
                meta["xmp"] = data.decode("utf-8", errors="replace")
            if size & 1:
                f.read(1)
        else:
            f.seek(size + (size & 1), os.SEEK_CUR)
    return True


def _iter_boxes(buf, start, end):
    pos = start
    while pos + 8 <= end:
        size = struct.unpack(">I", buf[pos:pos + 4])[0]
        typ = buf[pos + 4:pos + 8]
        hdr = 8
        if size == 1:
            if pos + 16 > end:
                break
            size = struct.unpack(">Q", buf[pos + 8:pos + 16])[0]
            hdr = 16
        elif size == 0:
            size = end - pos
        if size < hdr or pos + size > end:
            break
        yield typ, pos, hdr, size
        pos += size


def _parse_heif(f, meta):
    """HEIC/HEIF/AVIF: položky 'Exif' a XMP (mime) podle boxů meta/iinf/iloc."""
    head = f.read(4 * 1024 * 1024)
    if len(head) < 12 or head[4:8] != b"ftyp":
        return False
    meta_box = None
    for typ, pos, hdr, size in _iter_boxes(head, 0, len(head)):
        if typ == b"meta":
            meta_box = (pos + hdr + 4, pos + size)   # FullBox
            break
    if meta_box is None:
        return False
    meta["found"] = True
    items = {}
    locs = {}
    ms, me = meta_box
    for typ, pos, hdr, size in _iter_boxes(head, ms, me):
        if typ == b"iinf":
            ver = head[pos + hdr]
            p = pos + hdr + 4
            p += 2 if ver == 0 else 4
            for t2, p2, h2, s2 in _iter_boxes(head, p, pos + size):
                if t2 != b"infe":
                    continue
                iv = head[p2 + h2]
                q = p2 + h2 + 4
                if iv < 2:
                    continue
                if iv == 2:
                    iid = struct.unpack(">H", head[q:q + 2])[0]; q += 2
                else:
                    iid = struct.unpack(">I", head[q:q + 4])[0]; q += 4
                q += 2  # protection index
                itype = head[q:q + 4]; q += 4
                ctype = b""
                if itype == b"mime":
                    rest = head[q:p2 + s2].split(b"\x00")
                    ctype = rest[1] if len(rest) > 1 else b""
                items[iid] = (itype, ctype)
        elif typ == b"iloc":
            ver = head[pos + hdr]
            p = pos + hdr + 4
            b1, b2 = head[p], head[p + 1]
            off_sz, len_sz, base_sz = b1 >> 4, b1 & 15, b2 >> 4
            idx_sz = (b2 & 15) if ver in (1, 2) else 0
            p += 2
            if ver < 2:
                cnt = struct.unpack(">H", head[p:p + 2])[0]; p += 2
            else:
                cnt = struct.unpack(">I", head[p:p + 4])[0]; p += 4

            def rd(sz):
                nonlocal p
                if sz == 0:
                    return 0
                v = int.from_bytes(head[p:p + sz], "big"); p += sz
                return v
            for _ in range(cnt):
                if ver < 2:
                    iid = rd(2)
                else:
                    iid = rd(4)
                cm = 0
                if ver in (1, 2):
                    cm = rd(2) & 15
                rd(2)  # data reference index
                base = rd(base_sz)
                ecnt = rd(2)
                exts = []
                for _ in range(ecnt):
                    if idx_sz:
                        rd(idx_sz)
                    eo = rd(off_sz)
                    el = rd(len_sz)
                    exts.append((base + eo, el))
                if cm == 0:
                    locs[iid] = exts

    def item_data(iid):
        out = b""
        for off, ln in locs.get(iid, []):
            f.seek(off)
            out += f.read(ln if ln else 1024 * 1024)
        return out

    for iid, (itype, ctype) in items.items():
        if itype == b"Exif" and iid in locs:
            d = item_data(iid)
            if len(d) >= 4:
                toff = struct.unpack(">I", d[:4])[0]
                blk = d[4 + toff:]
                if not (blk[:2] in (b"II", b"MM")):
                    i = d.find(b"Exif\x00\x00")
                    blk = d[i + 6:] if i >= 0 else blk
                _parse_tiff_into(_Src(blk), meta)
        elif itype == b"mime" and (b"xmp" in ctype.lower() or b"rdf+xml" in ctype.lower()):
            if meta["xmp"] is None and iid in locs:
                meta["xmp"] = item_data(iid).decode("utf-8", errors="replace")
    return True


def _scan_tiff_blocks(buf, meta):
    """Záloha (CR3, neznámé kontejnery): projde TIFF hlavičky v bufferu a sloučí nalezené údaje."""
    for sig in (b"II\x2a\x00", b"MM\x00\x2a"):
        idx = 0
        while True:
            idx = buf.find(sig, idx)
            if idx < 0:
                break
            try:
                _parse_tiff_into(_Src(buf[idx:]), meta)
            except Exception:
                pass
            idx += 4
    if meta["xmp"] is None:
        i = buf.find(b"<x:xmpmeta")
        if i >= 0:
            j = buf.find(b"</x:xmpmeta>", i)
            if j > i:
                meta["xmp"] = buf[i:j + 12].decode("utf-8", errors="replace")


def _read_meta(filepath):
    """Načte EXIF/XMP fotky do slovníku meta (formát se určuje podle obsahu, ne přípony)."""
    meta = _new_meta()
    ext = net_ext(filepath).lower()
    with open(filepath, "rb") as f:
        head = f.read(16)
        f.seek(0)
        if head[:2] == b"\xff\xd8":
            _parse_jpeg_bytes(_read_jpeg_head(f), meta)
        elif head[:4] in (b"II*\x00", b"MM\x00*", b"IIRO", b"IIRS", b"IIU\x00", b"MMOR"):
            buf = f.read(2 * 1024 * 1024)
            _parse_tiff_into(_Src(buf, f, 0), meta)
        elif head[:8] == b"\x89PNG\r\n\x1a\n":
            _parse_png(f, meta)
        elif head[:4] == b"RIFF" and head[8:12] == b"WEBP":
            _parse_webp(f, meta)
        elif head[:15] == b"FUJIFILMCCD-RAW":
            hdr = f.read(100)
            if len(hdr) >= 92:
                joff, jlen = struct.unpack(">II", hdr[84:92])
                f.seek(joff)
                _parse_jpeg_bytes(f.read(min(jlen, 64 * 1024 * 1024)), meta)
        elif head[4:8] == b"ftyp":
            brand = head[8:12]
            if brand == b"crx " or ext == ".cr3":
                meta["found"] = True
                _scan_tiff_blocks(f.read(4 * 1024 * 1024), meta)
            else:
                if not _parse_heif(f, meta) or (meta["date_orig"] is None and meta["gps"] is None):
                    f.seek(0)
                    _scan_tiff_blocks(f.read(4 * 1024 * 1024), meta)
    return meta


# --- XMP vložené ve fotce (odpovídá dotazům WIC /xmp/exif:...) ---
def _xmp_prop(xmp, name):
    m = re.search(r'(?<![A-Za-z])' + re.escape(name) + r'\s*(?:>|=\s*"|=\s*\')\s*([^<"\']+)', xmp)
    return m.group(1).strip() if m else None


def _xmp_date_taken(xmp):
    """Náhrada System.Photo.DateTaken z XMP: exif:DateTimeOriginal, xmp:CreateDate (pásmo -> místní čas PC)."""
    for key in ("exif:DateTimeOriginal", "xmp:CreateDate"):
        v = _xmp_prop(xmp, key)
        if not v:
            continue
        m = ISO_DATE_REGEX.match(v.strip())
        if m:
            try:
                sec = int(m.group(6)) if m.group(6) else 0
                dt = datetime.datetime(int(m.group(1)), int(m.group(2)), int(m.group(3)),
                                       int(m.group(4)), int(m.group(5)), sec)
                tz = m.group(7)
                if tz:
                    if tz.upper() == "Z":
                        dt = _utc_to_local(dt)
                    else:
                        sign = 1 if tz[0] == "+" else -1
                        digits = tz[1:].replace(":", "")
                        off = datetime.timedelta(hours=int(digits[:2]), minutes=int(digits[2:4] or 0))
                        dt = _utc_to_local(dt - sign * off)
                if is_valid_year(dt.year):
                    return dt.strftime("%Y%m%d_%H%M%S")
            except Exception:
                pass
        r = try_raw_exif_date(v)
        if r:
            return r
    return None


def _decode_rational_text(s):
    """DecodeExifRationalValue pro text: 'num/den' nebo číslo."""
    if s is None:
        return None
    s = s.strip()
    try:
        if "/" in s:
            a, b = s.split("/", 1)
            b = float(b)
            if b == 0:
                return None
            v = float(a) / b
        else:
            v = float(s)
        if math.isnan(v) or math.isinf(v):
            return None
        return v
    except Exception:
        return None


def read_photo_metadata(filepath):
    """
    ProcessPhotoFile: vrací (date_str nebo None, lat, lon, alt, has_gps, date_quality).
    Datum: EXIF DateTimeOriginal -> XMP (DateTaken) -> EXIF DateTimeDigitized.
    Poloha: EXIF GPS -> XMP exif:GPSLatitude/GPSLongitude.
    Výška: EXIF GPS 6/5 -> XMP exif:GPSAltitude/GPSAltitudeRef (neplatná hodnota = další zdroj).
    """
    try:
        meta = _read_meta(filepath)
    except Exception:
        meta = _new_meta()

    if not meta["found"] and HAS_PILLOW:
        _pillow_meta(filepath, meta)

    xmp = meta["xmp"] or ""
    date_str = meta["date_orig"]
    if date_str is None and xmp:
        date_str = _xmp_date_taken(xmp)
    if date_str is None:
        date_str = meta["date_dig"]

    lat = lon = None
    has_gps = False
    if meta["gps"] is not None:
        la, lo = meta["gps"]
        if (abs(la) > 0.0001 or abs(lo) > 0.0001) and abs(la) <= 90.0 and abs(lo) <= 180.0:
            lat, lon, has_gps = round_net(la, 6), round_net(lo, 6), True
    if not has_gps and xmp:
        xla = parse_xmp_coordinate(_xmp_prop(xmp, "exif:GPSLatitude"))
        xlo = parse_xmp_coordinate(_xmp_prop(xmp, "exif:GPSLongitude"))
        if xla is not None and xlo is not None and (abs(xla) > 0.0001 or abs(xlo) > 0.0001) \
                and abs(xla) <= 90.0 and abs(xlo) <= 180.0:
            lat, lon, has_gps = round_net(xla, 6), round_net(xlo, 6), True

    alt = None
    if meta["alt_raw"] is not None:
        raw = meta["alt_raw"]
        alt = PhotoRecordItem.valid_altitude(-abs(raw) if meta["alt_ref"] == 1 else raw)
    if alt is None and xmp:
        v = _decode_rational_text(_xmp_prop(xmp, "exif:GPSAltitude"))
        if v is not None:
            ref = (_xmp_prop(xmp, "exif:GPSAltitudeRef") or "0").strip()
            alt = PhotoRecordItem.valid_altitude(-abs(v) if ref == "1" else v)

    dq = 2 if date_str else 0
    return date_str, (lat or 0.0), (lon or 0.0), alt, has_gps, dq


def _pillow_meta(filepath, meta):
    """Poslední záloha přes Pillow (jen když vlastní parsery formát nepoznaly)."""
    try:
        with Image.open(filepath) as img:
            exif = img.getexif()
            if not exif:
                return
            meta["found"] = True
            try:
                sub = exif.get_ifd(ExifTags.IFD.Exif)
            except Exception:
                sub = {}
            meta["date_orig"] = try_raw_exif_date(sub.get(36867))
            meta["date_dig"] = try_raw_exif_date(sub.get(36868))
            try:
                gps = exif.get_ifd(ExifTags.IFD.GPSInfo)
            except Exception:
                gps = {}
            if gps and gps.get(2) and gps.get(4):
                la = _gps_to_decimal([float(x) for x in gps[2]], gps.get(1))
                lo = _gps_to_decimal([float(x) for x in gps[4]], gps.get(3))
                if la is not None and lo is not None:
                    meta["gps"] = (la, lo)
            if gps and gps.get(6) is not None:
                meta["alt_raw"] = float(gps[6])
                r = gps.get(5, 0)
                if isinstance(r, (bytes, bytearray)):
                    r = r[0] if r else 0
                meta["alt_ref"] = 1 if r == 1 else 0
    except Exception:
        pass


def read_photo_date(filepath):
    """ReadPhotoDate pro statistiku (EXIF -> XMP -> Digitized), jinak None."""
    try:
        meta = _read_meta(filepath)
    except Exception:
        return None
    if not meta["found"] and HAS_PILLOW:
        _pillow_meta(filepath, meta)
    d = meta["date_orig"]
    if d is None and meta["xmp"]:
        d = _xmp_date_taken(meta["xmp"])
    if d is None:
        d = meta["date_dig"]
    return d


# ==============================================================================
# VIDEO (MP4, MOV, M4V, 3GP ... - moov atom) - shodné s BAT
# ==============================================================================
def read_moov(filepath):
    """ReadMoov: obsah atomu moov (max 64 MB), None = soubor moov nemá (AVI, MKV, MTS ...)."""
    with open(filepath, "rb") as f:
        f.seek(0, os.SEEK_END)
        length = f.tell()
        pos = 0
        while pos + 8 <= length:
            f.seek(pos)
            hdr = f.read(8)
            if len(hdr) < 8:
                break
            box_size = struct.unpack(">I", hdr[:4])[0]
            header_size = 8
            if box_size == 1:
                lrg = f.read(8)
                if len(lrg) < 8:
                    break
                box_size = struct.unpack(">Q", lrg)[0]
                header_size = 16
            elif box_size == 0:
                box_size = length - pos
            if box_size < header_size:
                break
            if hdr[4:8] == b"moov":
                return f.read(min(box_size - header_size, 64 * 1024 * 1024))
            pos += box_size
    return None


def _be32(b, p):
    return struct.unpack(">i", b[p:p + 4])[0]


def _type_at(b, p, t):
    return 0 <= p and p + 4 <= len(b) and b[p:p + 4] == t


def find_apple_key_value(moov, wanted):
    """FindAppleKeyValue: hodnota klíče z moov/meta/keys + ilst."""
    wanted_b = wanted
    n = len(moov)
    i = moov.find(b"keys", 4)
    while 0 <= i and i + 12 <= n:
        box_start = i - 4
        box_size = _be32(moov, box_start)
        if box_size >= 16 and box_start + box_size <= n:
            count = _be32(moov, i + 8)
            if 0 < count <= 10000:
                p = i + 12
                box_end = box_start + box_size
                wanted_index = -1
                k = 1
                while k <= count and p + 8 <= box_end:
                    ks = _be32(moov, p)
                    if ks < 8 or p + ks > box_end:
                        break
                    key = moov[p + 8:p + ks].decode("utf-8", errors="replace")
                    if key == wanted_b:
                        wanted_index = k
                        break
                    p += ks
                    k += 1
                if wanted_index >= 0:
                    j = moov.find(b"ilst", box_end + 4)
                    while 0 <= j and j + 4 <= n:
                        il_start = j - 4
                        il_size = _be32(moov, il_start)
                        if il_size < 8 or il_start + il_size > n:
                            j = moov.find(b"ilst", j + 1)
                            continue
                        il_end = il_start + il_size
                        q = j + 4
                        while q + 8 <= il_end:
                            it_size = _be32(moov, q)
                            if it_size < 8 or q + it_size > il_end:
                                break
                            it_index = _be32(moov, q + 4)
                            if it_index == wanted_index:
                                d = q + 8
                                while d + 16 <= q + it_size:
                                    d_size = _be32(moov, d)
                                    if d_size < 16 or d + d_size > q + it_size:
                                        break
                                    if _type_at(moov, d + 4, b"data"):
                                        return moov[d + 16:d + d_size].decode("utf-8", errors="replace")
                                    d += d_size
                            q += it_size
                        break
        i = moov.find(b"keys", i + 1)
    return None


ISO6709_REGEX = re.compile(r'([+-]\d{1,3}(?:\.\d+)?)([+-]\d{1,3}(?:\.\d+)?)([+-]\d{1,5}(?:\.\d+)?)?')


def try_parse_iso6709(s):
    """TryParseIso6709: (lat, lon, alt) bez zaokrouhlení, nebo None."""
    if not s:
        return None
    m = ISO6709_REGEX.search(s)
    if not m:
        return None
    lat = float(m.group(1))
    lon = float(m.group(2))
    if abs(lat) > 90.0 or abs(lon) > 180.0:
        return None
    if abs(lat) < 0.0001 and abs(lon) < 0.0001:
        return None
    alt = PhotoRecordItem.valid_altitude(float(m.group(3))) if m.group(3) else None
    return lat, lon, alt


def try_parse_loci(moov):
    """TryParseLoci: 3GPP 'loci' - jazyk, název (UTF-8 + nula), role, pak DÉLKA, ŠÍŘKA, VÝŠKA (16.16)."""
    n = len(moov)
    i = moov.find(b"loci", 4)
    while 0 <= i and i + 4 <= n:
        box_start = i - 4
        box_size = _be32(moov, box_start)
        if box_size >= 8 + 4 + 2 + 1 + 1 + 12 and box_start + box_size <= n:
            box_end = box_start + box_size
            p = i + 4 + 4 + 2
            while p < box_end and moov[p] != 0:
                p += 1
            p += 1  # nulový bajt
            p += 1  # role
            if p + 12 <= box_end:
                lo = _be32(moov, p) / 65536.0
                la = _be32(moov, p + 4) / 65536.0
                al = _be32(moov, p + 8) / 65536.0
                if abs(la) <= 90.0 and abs(lo) <= 180.0 and not (abs(la) < 0.0001 and abs(lo) < 0.0001):
                    return la, lo, PhotoRecordItem.valid_altitude(al)
        i = moov.find(b"loci", i + 1)
    return None


def read_mvhd_raw(moov):
    """ReadMvhdRaw: creation_time z mvhd jako 'neprevedený' čas, nebo None."""
    n = len(moov)
    i = moov.find(b"mvhd", 4)
    while 0 <= i and i + 16 <= n:
        box_size = _be32(moov, i - 4)
        if not (box_size < 20 or i - 4 + box_size > n):
            ver = moov[i + 4]
            if ver == 1:
                secs = struct.unpack(">Q", moov[i + 8:i + 16])[0]
            else:
                secs = struct.unpack(">I", moov[i + 8:i + 12])[0]
            if secs == 0 or secs > 6000000000:
                return None
            raw = datetime.datetime(1904, 1, 1) + datetime.timedelta(seconds=secs)
            if raw.year < 1990 or raw > datetime.datetime.now() + datetime.timedelta(days=2):
                return None
            return raw
        i = moov.find(b"mvhd", i + 1)
    return None


def read_video_date(moov, file_name):
    """ReadVideoDate: (date_str, quality) nebo (None, 0)."""
    try:
        apple = find_apple_key_value(moov, "com.apple.quicktime.creationdate")
    except Exception:
        apple = None
    if apple:
        r = parse_iso_wall_clock(apple.strip("\0 "))
        if r:
            return r, 2
    try:
        raw = read_mvhd_raw(moov)
    except Exception:
        raw = None
    if raw is not None:
        fn = parse_filename_datetime_only(net_name_wo_ext(file_name))
        if fn is not None and abs((fn - raw).total_seconds()) <= 300:
            return raw.strftime("%Y%m%d_%H%M%S"), 2   # kamera zapsala místní čas
        try:
            return _utc_to_local(raw).strftime("%Y%m%d_%H%M%S"), 1
        except Exception:
            return None, 0
    return None, 0


def get_video_date_string(video_path):
    """GetVideoDateString: (date_str nebo None, quality)."""
    try:
        moov = read_moov(video_path)
        if moov is not None:
            return read_video_date(moov, os.path.basename(video_path))
    except Exception:
        pass
    return None, 0


def process_video(filepath, root_dir):
    """ProcessVideoGps + ExtractQuickTimeGps. None = video nemá moov / nejde přečíst."""
    try:
        moov = read_moov(filepath)
        if moov is None:
            return None
        st = os.stat(filepath)
        fname = os.path.basename(filepath)
        mtime = datetime.datetime.fromtimestamp(st.st_mtime)
        cands = []

        i = moov.find(b"\xa9xyz")
        while i >= 0:
            take = min(160, len(moov) - (i + 4))
            if take > 0:
                txt = moov[i + 4:i + 4 + take].decode("ascii", errors="replace")
                r = try_parse_iso6709(txt)
                if r:
                    cands.append(r)
                    break
            i = moov.find(b"\xa9xyz", i + 1)

        try:
            r = try_parse_iso6709(find_apple_key_value(moov, "com.apple.quicktime.location.ISO6709"))
            if r:
                cands.append(r)
        except Exception:
            pass

        try:
            r = try_parse_loci(moov)
            if r:
                cands.append(r)
        except Exception:
            pass

        v_date, v_q = read_video_date(moov, fname)
        rel = make_rel_path(filepath, root_dir)
        if not cands:
            return PhotoRecordItem(
                file_name=fname, file_size_bytes=st.st_size, relative_path=rel,
                date_taken_str=v_date if v_date else parse_date_to_full_str(None, fname, mtime),
                date_quality=v_q if v_date else 0, has_gps=False)

        best = cands[0]
        alt = best[2]
        if alt is None:
            for c in cands:
                if c[2] is None:
                    continue
                if abs(c[0] - best[0]) < 0.001 and abs(c[1] - best[1]) < 0.001:
                    alt = c[2]
                    break
        rec = PhotoRecordItem(
            file_name=fname, date_taken_str=parse_date_to_full_str(None, fname, mtime),
            latitude=round_net(best[0], 6), longitude=round_net(best[1], 6), altitude=alt,
            file_size_bytes=st.st_size, relative_path=rel, has_gps=True)
        if v_date:
            rec.date_taken_str = v_date
            rec.date_quality = v_q
        return rec
    except Exception:
        return None


# ==============================================================================
# SIDECAR SOUBORY (Google Photos JSON, XMP, DJI SRT) - shodné s BAT
# ==============================================================================
_INVALID_FN_CHARS = set('"<>|\0:*?\\/') | {chr(c) for c in range(1, 32)}
EDITED_SUFFIXES = ("-edited", "-upraveno", "-upravené", "-bearbeitet", "-modifié", "-editado",
                   "-modificato", "-bewerkt", "-edytowane", "-redigerad", "-muokattu")
_NUM = r'([-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?)'


def make_rel_path(full_path, root_dir):
    rel = os.path.relpath(full_path, root_dir)
    if os.sep != "/":
        rel = rel.replace(os.sep, "/")
    if os.altsep and os.altsep != "/":
        rel = rel.replace(os.altsep, "/")
    return rel


def json_unescape(s):
    if "\\" not in s:
        return s

    def rep(m):
        e = m.group(1)
        if len(e) == 5:
            return chr(int(e[1:], 16))
        return {"n": "\n", "t": "\t", "r": "\r", "b": "\b", "f": "\f"}.get(e[0], e)
    out = re.sub(r'\\(u[0-9a-fA-F]{4}|.)', rep, s)
    try:  # spojit náhradní páry UTF-16 (emoji)
        out = out.encode("utf-16", "surrogatepass").decode("utf-16")
    except Exception:
        pass
    return out


def google_json_photo_candidates(json_path):
    """GoogleJsonPhotoCandidates: názvy fotky odvozené z názvu JSON (vč. .supplemental-metadata)."""
    d = os.path.dirname(json_path)
    name = net_name_wo_ext(os.path.basename(json_path))
    names = [name]
    last_dot = name.rfind(".")
    if last_dot > 0:
        seg = name[last_dot + 1:].lower()
        m = re.match(r'^(.*?)(\(\d+\))?$', seg)
        core = m.group(1)
        copy_no = m.group(2) or ""
        if len(core) >= 2 and "supplemental-metadata".startswith(core):
            names.append(name[:last_dot] + copy_no)
    extra = []
    for nm in names:
        m = re.match(r'^(.+?)(\.[A-Za-z0-9]{2,5})\((\d+)\)$', nm)
        if m:
            extra.append(m.group(1) + "(" + m.group(3) + ")" + m.group(2))
    names.extend(extra)
    return [os.path.join(d, nm) for nm in names if nm and is_valid_media_file(nm)]


def google_json_companions(photo_path, idx):
    """GoogleJsonCompanions: upravené kopie a video Live Photo bez vlastního JSON."""
    out = []
    try:
        d = os.path.dirname(photo_path)
        fn = os.path.basename(photo_path)
        bn = net_name_wo_ext(fn)
        ext = net_ext(fn)
        cands = []
        for suf in EDITED_SUFFIXES:
            cands.append(os.path.join(d, bn + suf + ext))
            if ext.lower() != ".jpg":
                cands.append(os.path.join(d, bn + suf + ".jpg"))
        if ext.lower() in (".heic", ".heif", ".jpg", ".jpeg"):
            cands.append(os.path.join(d, bn + ".mp4"))
            cands.append(os.path.join(d, bn + ".mov"))
        seen = set()
        for c in cands:
            real = idx.find(c)
            if real is None:
                continue
            if idx.exists(real + ".json") or idx.exists(real + ".supplemental-metadata.json"):
                continue
            if real.lower() in seen:
                continue
            seen.add(real.lower())
            out.append(real)
    except Exception:
        pass
    return out


def process_google_json(json_path, root_dir, idx):
    """ProcessGoogleJson: (záznam, cesta_k_fotce) nebo (None, None). Bez platné polohy se JSON nepoužije."""
    try:
        content = read_text_net(json_path)
        if '"latitude"' not in content or '"longitude"' not in content:
            return None, None

        mt = re.search(r'"title"\s*:\s*"((?:[^"\\]|\\.)+)"', content)
        title = json_unescape(mt.group(1)) if mt else net_name_wo_ext(os.path.basename(json_path))
        if any(c in _INVALID_FN_CHARS for c in title):
            title = net_name_wo_ext(os.path.basename(json_path))

        lat = lon = 0.0
        alt = None
        got = False
        for g in re.finditer(r'"geoData(?:Exif)?"\s*:\s*\{[^}]*\}', content):
            gt = g.group(0)
            m_la = re.search(r'"latitude"\s*:\s*' + _NUM, gt)
            m_lo = re.search(r'"longitude"\s*:\s*' + _NUM, gt)
            if not m_la or not m_lo:
                continue
            g_la, g_lo = float(m_la.group(1)), float(m_lo.group(1))
            if abs(g_la) < 0.0001 and abs(g_lo) < 0.0001:
                continue
            if abs(g_la) > 90.0 or abs(g_lo) > 180.0:
                continue
            lat, lon, got = g_la, g_lo, True
            m_al = re.search(r'"altitude"\s*:\s*' + _NUM, gt)
            if m_al:
                alt = PhotoRecordItem.valid_altitude(float(m_al.group(1)))
            break

        if not got:
            m_la = re.search(r'"latitude"\s*:\s*([-+]?[0-9]*\.?[0-9]+)', content)
            m_lo = re.search(r'"longitude"\s*:\s*([-+]?[0-9]*\.?[0-9]+)', content)
            if not m_la or not m_lo:
                return None, None
            lat, lon = float(m_la.group(1)), float(m_lo.group(1))
            if abs(lat) < 0.0001 and abs(lon) < 0.0001:
                return None, None
            if abs(lat) > 90.0 or abs(lon) > 180.0:
                return None, None
            m_al = re.search(r'"altitude"\s*:\s*([-+]?[0-9]*\.?[0-9]+)', content)
            if m_al:
                alt = PhotoRecordItem.valid_altitude(float(m_al.group(1)))

        date_str = DATE_ZERO
        dq = 0
        m_t = re.search(r'"photoTakenTime"\s*:\s*\{[^}]*"timestamp"\s*:\s*"?([0-9]{9,18})"?', content)
        if m_t:
            raw_ts = m_t.group(1)
            epoch = int(raw_ts)
            if len(raw_ts) >= 16:
                epoch //= 1000000
            elif len(raw_ts) >= 13:
                epoch //= 1000
            dt = datetime.datetime.fromtimestamp(epoch, tz=timezone.utc).astimezone().replace(tzinfo=None)
            date_str = dt.strftime("%Y%m%d_%H%M%S")
            dq = 1

        jdir = os.path.dirname(json_path)
        photo_path = os.path.join(jdir, title)
        for cand in google_json_photo_candidates(json_path):
            real = idx.find(cand)
            if real is not None:
                photo_path = real
                title = os.path.basename(real)
                break
        real = idx.find(photo_path)
        photo_out = None
        if real is not None:
            fsize = os.path.getsize(real)
            rel = make_rel_path(real, root_dir)
            photo_out = real
        else:
            fsize = 0
            rel = make_rel_path(json_path, root_dir)

        return PhotoRecordItem(file_name=title, date_taken_str=date_str, date_quality=dq,
                               latitude=round_net(lat, 6), longitude=round_net(lon, 6), altitude=alt,
                               file_size_bytes=fsize, relative_path=rel, has_gps=True), photo_out
    except Exception:
        return None, None


def parse_xmp_coordinate(val):
    """ParseXmpCoordinate: '50.123', '50,7.38N', '50 7 22.8 N' ..."""
    if not val or not isinstance(val, str) or not val.strip():
        return None
    val = val.strip()
    is_neg = val[-1:].upper() in ("S", "W")
    val = re.sub(r'[NSEWnsew]$', '', val).strip()
    parts = [p for p in re.split(r'[, ;]', val) if p]
    try:
        if len(parts) == 1:
            dec = float(parts[0])
        elif len(parts) == 2:
            dec = float(parts[0]) + float(parts[1]) / 60.0
        elif len(parts) >= 3:
            dec = float(parts[0]) + float(parts[1]) / 60.0 + float(parts[2]) / 3600.0
        else:
            return None
    except Exception:
        return None
    return -dec if is_neg else dec


_XMP_VIDEO_PHOTO_EXTS = (
    ".dng", ".cr2", ".cr3", ".nef", ".arw", ".raf", ".orf", ".rw2", ".pef", ".srw",
    ".jpg", ".jpeg", ".heic", ".heif", ".avif", ".tif", ".tiff", ".png", ".webp", ".bmp", ".gif",
    ".mp4", ".mov", ".m4v", ".avi", ".mkv", ".wmv", ".3gp", ".mts", ".m2ts", ".mpg", ".mpeg"
)


def process_xmp_file(xmp_path, root_dir, idx):
    """ProcessXmpFile: záznam s polohou, nebo None."""
    try:
        content = read_text_net(xmp_path)
        m_la = re.search(r'GPSLatitude(?!Ref)\s*(?:>|=\s*"|=\s*\')\s*([^<"\']+)', content, re.IGNORECASE)
        m_lo = re.search(r'GPSLongt?itude(?!Ref)\s*(?:>|=\s*"|=\s*\')\s*([^<"\']+)', content, re.IGNORECASE)
        lat = parse_xmp_coordinate(m_la.group(1)) if m_la else None
        lon = parse_xmp_coordinate(m_lo.group(1)) if m_lo else None
        has_ll = lat is not None and lon is not None
        has_gps = has_ll and not (abs(lat) < 0.0001 and abs(lon) < 0.0001) \
            and not (abs(lat) > 90.0 or abs(lon) > 180.0)

        date_str = DATE_ZERO
        dq = 0
        xmp_date = None
        found = False
        for key in ("DateTimeOriginal", "DateCreated", "CreateDate"):
            for md in re.finditer(r'(?<![A-Za-z])' + key + r'\s*(?:>|=\s*"|=\s*\')\s*([^<"\']+)', content):
                v = md.group(1).strip()
                if len(v) < 4:
                    continue
                if xmp_date is None:
                    xmp_date = v
                if v.find(":") > 0 and re.search(r'\d[T ]\d', v):
                    xmp_date = v
                    found = True
                    break
            if found:
                break
        if xmp_date is not None:
            date_str = parse_date_to_full_str(xmp_date, os.path.basename(xmp_path), file_mtime_dt(xmp_path))
            dq = 2

        alt = None
        m_al = re.search(r'GPSAltitude(?!Ref)\s*(?:>|=\s*"|=\s*\')\s*([^<"\']+)', content, re.IGNORECASE)
        m_ref = re.search(r'GPSAltitudeRef\s*(?:>|=\s*"|=\s*\')\s*([^<"\']+)', content, re.IGNORECASE)
        if m_al:
            v = _decode_rational_text(m_al.group(1))
            if v is not None:
                ref = m_ref.group(1).strip() if m_ref else "0"
                alt = PhotoRecordItem.valid_altitude(-abs(v) if ref == "1" else v)
        if alt is None:
            m_abs = re.search(r'AbsoluteAltitude(?:>|="|=\')\s*"?([+-]?\d+(?:\.\d+)?)', content)
            if m_abs:
                alt = PhotoRecordItem.valid_altitude(float(m_abs.group(1)))

        if not has_gps:
            return None

        d = os.path.dirname(xmp_path)
        base = net_name_wo_ext(os.path.basename(xmp_path))
        title = base
        photo = None
        direct = idx.find(os.path.join(d, base))
        if direct is not None and not direct.lower().endswith(".xmp"):
            photo = direct
            title = os.path.basename(direct)
        else:
            for ext in _XMP_VIDEO_PHOTO_EXTS:
                real = idx.find(os.path.join(d, base + ext))
                if real is not None:
                    photo = real
                    title = os.path.basename(real)
                    break
        if photo is not None:
            fsize = os.path.getsize(photo)
            rel = make_rel_path(photo, root_dir)
        else:
            fsize = 0
            rel = make_rel_path(xmp_path, root_dir)

        return PhotoRecordItem(file_name=title, date_taken_str=date_str, date_quality=dq,
                               latitude=round_net(lat, 6), longitude=round_net(lon, 6), altitude=alt,
                               file_size_bytes=fsize, relative_path=rel, has_gps=True)
    except Exception:
        return None


_SRT_VIDEO_EXTS = (".mp4", ".mov", ".m4v", ".avi", ".mkv", ".wmv", ".3gp", ".flv", ".mts", ".m2ts", ".mpg", ".mpeg")


def process_srt_file(srt_path, root_dir, idx):
    """ProcessSrtFile (DJI titulky): záznam s polohou, nebo None."""
    try:
        content = read_text_net(srt_path)
        re_lat = re.compile(r'(?<![A-Za-z_])(?:latitude|lat)\s*[:=]\s*([+-]?\d+(?:\.\d+)?)', re.IGNORECASE)
        re_lon = re.compile(r'(?<![A-Za-z_])(?:longt?itude|lon|long|lng)\s*[:=]\s*([+-]?\d+(?:\.\d+)?)', re.IGNORECASE)
        re_gps = re.compile(r'GPS\s*[(:]\s*([+-]?\d+(?:\.\d+)?)\s*,\s*([+-]?\d+(?:\.\d+)?)')
        re_alt = re.compile(r'(?<![A-Za-z_])(?:abs_alt|absoluteAltitude)\s*[:=]\s*([+-]?\d+(?:\.\d+)?)', re.IGNORECASE)

        lat = lon = 0.0
        alt = None
        found = False
        blocks = re.split(r'\r?\n[ \t]*\r?\n', content)
        for bi, blk in enumerate(blocks):
            m_la = re_lat.search(blk)
            m_lo = re_lon.search(blk)
            if m_la and m_lo:
                b_lat, b_lon = float(m_la.group(1)), float(m_lo.group(1))
            else:
                m = re_gps.search(blk)
                if not m:
                    continue
                v1, v2 = float(m.group(1)), float(m.group(2))
                b_lon, b_lat = v1, v2           # DJI: GPS(délka, šířka, výška)
                if abs(b_lat) > 90.0 and abs(b_lon) <= 90.0:
                    b_lat, b_lon = v1, v2
            if abs(b_lat) > 90.0 or abs(b_lon) > 180.0:
                continue
            if abs(b_lat) < 0.0001 and abs(b_lon) < 0.0001:
                continue
            lat, lon, found = b_lat, b_lon, True
            for ai in range(bi, len(blocks)):
                if alt is not None:
                    break
                m_a = re_alt.search(blocks[ai])
                if m_a:
                    alt = PhotoRecordItem.valid_altitude(float(m_a.group(1)))
            break
        if not found:
            return None

        d = os.path.dirname(srt_path)
        base = net_name_wo_ext(os.path.basename(srt_path))
        title = base
        fsize = 0
        actual = srt_path
        for vx in _SRT_VIDEO_EXTS:
            real = idx.find(os.path.join(d, base + vx))
            if real is not None:
                actual = real
                title = os.path.basename(real)
                fsize = os.path.getsize(real)
                break

        rec = PhotoRecordItem(file_name=title,
                              date_taken_str=parse_date_to_full_str(None, title, file_mtime_dt(actual)),
                              latitude=round_net(lat, 6), longitude=round_net(lon, 6), altitude=alt,
                              file_size_bytes=fsize, relative_path=make_rel_path(actual, root_dir), has_gps=True)
        srt_date = None
        srt_q = 2
        m_d = re.search(r'(?<!\d)((?:19|20)\d\d)[-./](\d{2})[-./](\d{2})[ T]+(\d{2}):(\d{2}):(\d{2})', content)
        if m_d:
            srt_date = parse_iso_wall_clock("{0}-{1}-{2}T{3}:{4}:{5}".format(*m_d.groups()))
        if srt_date is None and actual.lower() != srt_path.lower():
            srt_date, srt_q = get_video_date_string(actual)
        if srt_date is not None:
            rec.date_taken_str = srt_date
            rec.date_quality = srt_q
        return rec
    except Exception:
        return None


def merge_sidecar_record(results, no_gps, r):
    """
    MergeSidecarRecord:
    - existuje-li už záznam G se stejnou cestou, jen se doplní chybějící výška;
    - je-li soubor zatím S, sidecar mu dodá souřadnice; datum vlastního souboru má přednost,
      sidecar vyhraje jen s důvěryhodnějším datem; vlastní výška souboru má přednost.
    """
    key = r.relative_path.lower()
    ex = results.get(key)
    if ex is not None:
        if ex.altitude is None and r.altitude is not None:
            ex.altitude = r.altitude
        return
    s = no_gps.pop(key, None)
    if s is not None:
        r_no_date = not r.date_taken_str or r.date_taken_str.startswith("00000000")
        if s.date_taken_str and (r_no_date or s.date_quality >= r.date_quality):
            r.date_taken_str = s.date_taken_str
            r.date_quality = s.date_quality
        if s.altitude is not None:
            r.altitude = s.altitude
        if r.file_size_bytes == 0:
            r.file_size_bytes = s.file_size_bytes
        r.file_name = s.file_name
        r.relative_path = s.relative_path
    results[key] = r


# ==============================================================================
# ZPRACOVÁNÍ FOTKY (pro paralelní běh)
# ==============================================================================
def process_photo(args):
    filepath, root_dir = args
    fname = os.path.basename(filepath)
    rec = PhotoRecordItem(file_name=fname, relative_path=make_rel_path(filepath, root_dir))
    try:
        st = os.stat(filepath)
        rec.file_size_bytes = st.st_size
        mtime = datetime.datetime.fromtimestamp(st.st_mtime)
    except Exception:
        mtime = datetime.datetime(1601, 1, 1)
    try:
        date_str, lat, lon, alt, has_gps, dq = read_photo_metadata(filepath)
        if date_str:
            rec.date_taken_str = date_str
            rec.date_quality = 2
        if has_gps:
            rec.latitude, rec.longitude, rec.has_gps = lat, lon, True
        if alt is not None:
            rec.altitude = alt   # výška se uloží vždy (souřadnice může dodat sidecar)
    except Exception:
        pass
    if not rec.date_taken_str:
        rec.date_taken_str = parse_date_to_full_str(None, fname, mtime)
    return rec


def process_video_entry(args):
    filepath, root_dir = args
    r = process_video(filepath, root_dir)
    if r is not None and r.has_gps:
        return r
    fname = os.path.basename(filepath)
    try:
        size = os.path.getsize(filepath)
    except Exception:
        size = 0
    if r is not None and r.date_taken_str:
        d, q = r.date_taken_str, r.date_quality
    else:
        d, q = parse_date_to_full_str(None, fname, file_mtime_dt(filepath)), 0
    return PhotoRecordItem(file_name=fname, file_size_bytes=size,
                           relative_path=make_rel_path(filepath, root_dir),
                           date_taken_str=d, date_quality=q, has_gps=False)


def get_file_date_string(filepath):
    """GetFileDateString (statistika): EXIF / metadata videa -> název -> datum změny."""
    fname = os.path.basename(filepath)
    ext = net_ext(fname).lower()
    if ext in PHOTO_EXTS:
        d = read_photo_date(filepath)
        if d:
            return d
    elif ext in VIDEO_EXTS:
        d, _ = get_video_date_string(filepath)
        if d:
            return d
    return parse_date_to_full_str(None, fname, file_mtime_dt(filepath))


# ==============================================================================
# SKENOVÁNÍ ARCHIVU A DEDUPLIKACE (Volba [1] a [2]) - shodné s BAT ScanAll
# ==============================================================================
def _sort_key(it):
    return (it.date_taken_str, _ord_ic_key(it.file_name), _ord_ic_key(it.relative_path))


def scan_archive(target_dir):
    start_time = time.time()
    clean_target = os.path.abspath(target_dir)

    photo_files, video_files, json_files, xmp_files, srt_files = [], [], [], [], []
    total_bytes = 0

    for root, dirs, files in os.walk(clean_target):
        dirs[:] = [d for d in dirs if not is_junk_dir_name(d.lower())]
        for f in files:
            n = f.lower()
            if is_own_output_file(n) or is_junk_file_name(n):
                continue
            full = os.path.join(root, f)
            if n.endswith(".json"):
                json_files.append(full)
            elif n.endswith(".xmp"):
                xmp_files.append(full)
            elif n.endswith(".srt"):
                srt_files.append(full)
            elif not is_valid_media_file(f):
                continue
            elif is_video_file(f):
                video_files.append(full)
                try: total_bytes += os.path.getsize(full)
                except Exception: pass
            else:
                photo_files.append(full)
                try: total_bytes += os.path.getsize(full)
                except Exception: pass

    for lst in (photo_files, video_files, json_files, xmp_files, srt_files):
        lst.sort(key=_ord_ic_key)

    results = {}   # G: klíč = relativní cesta malými písmeny
    no_gps = {}    # S
    idx = _DirIndex()
    workers = min(32, (os.cpu_count() or 4) * 2)

    with ThreadPoolExecutor(max_workers=workers) as ex:
        for r in ex.map(process_photo, [(p, clean_target) for p in photo_files]):
            key = r.relative_path.lower()
            if r.has_gps:
                results.setdefault(key, r)
            else:
                no_gps.setdefault(key, r)

        # Videa před sidecar soubory (stejné pořadí jako BAT)
        for r in ex.map(process_video_entry, [(v, clean_target) for v in video_files]):
            if r.has_gps:
                merge_sidecar_record(results, no_gps, r)
            else:
                no_gps.setdefault(r.relative_path.lower(), r)

    for j in json_files:
        r, j_photo = process_google_json(j, clean_target, idx)
        if r is None:
            continue
        if j_photo is not None:
            for comp in google_json_companions(j_photo, idx):
                try:
                    cr = PhotoRecordItem(file_name=os.path.basename(comp), date_taken_str=r.date_taken_str,
                                         date_quality=r.date_quality, latitude=r.latitude, longitude=r.longitude,
                                         altitude=r.altitude, file_size_bytes=os.path.getsize(comp),
                                         relative_path=make_rel_path(comp, clean_target), has_gps=True)
                    merge_sidecar_record(results, no_gps, cr)
                except Exception:
                    pass
        merge_sidecar_record(results, no_gps, r)

    for x in xmp_files:
        r = process_xmp_file(x, clean_target, idx)
        if r is not None:
            merge_sidecar_record(results, no_gps, r)

    for s in srt_files:
        r = process_srt_file(s, clean_target, idx)
        if r is not None:
            merge_sidecar_record(results, no_gps, r)

    gps_items = sorted(results.values(), key=_sort_key)
    gps_before_dedup = len(gps_items)

    # Deduplikace: 1) DATUM+NAZEV+LAT+LON  2) název bez přípony na stejném místě (4 desetinná místa)
    exact_seen = set()
    by_file_pos = {}
    dup_list = []

    def pos_key_of(r):
        return net_name_wo_ext(r.file_name).lower() + "|" + fmt_net(r.latitude, 4) + "|" + fmt_net(r.longitude, 4)

    for r in gps_items:
        exact_key = r.date_taken_str + "|" + r.file_name.lower() + "|" + fmt_net(r.latitude, 6) + "|" + fmt_net(r.longitude, 6)
        if exact_key in exact_seen:
            r.status = "D"
            dup_list.append(r)
            continue
        exact_seen.add(exact_key)

        pk = pos_key_of(r)
        existing = by_file_pos.get(pk)
        if existing is not None:
            if existing.date_taken_str.startswith("00000000") and not r.date_taken_str.startswith("00000000"):
                existing.status = "D"
                dup_list.append(existing)
                by_file_pos[pk] = r
            else:
                r.status = "D"
                dup_list.append(r)
            continue
        by_file_pos[pk] = r

    for r in dup_list:
        if r.altitude is None:
            continue
        kept = by_file_pos.get(pos_key_of(r))
        if kept is not None and kept.altitude is None:
            kept.altitude = r.altitude

    deduped_gps = list(by_file_pos.values())
    for g in deduped_gps:
        g.status = "G"
    for d in dup_list:
        if not d.status:
            d.status = "D"
    deduped_gps.sort(key=_sort_key)
    dup_list.sort(key=_sort_key)

    no_gps_items = list(no_gps.values())
    for s in no_gps_items:
        s.status = "S"
        s.altitude = None   # výška jen u záznamů s polohou
    no_gps_items.sort(key=_sort_key)

    all_records = deduped_gps + dup_list + no_gps_items
    all_records.sort(key=_sort_key)

    return {
        "total_files": len(photo_files) + len(video_files),
        "total_bytes": total_bytes,
        "gps_before_dedup": gps_before_dedup,
        "gps_records": deduped_gps,
        "dup_records": dup_list,
        "no_gps_records": no_gps_items,
        "all_records": all_records,
        "elapsed_sec": time.time() - start_time
    }


# ==============================================================================
# STATISTIKA ARCHIVU (Volba [3])
# ==============================================================================
def generate_folder_statistics(root_dir):
    clean_root = os.path.abspath(root_dir).rstrip("/\\")
    folder_stats = []

    for root, dirs, files in os.walk(clean_root):
        dirs[:] = [d for d in dirs if not is_junk_dir_name(d.lower())]
        dirs.sort(key=_ord_ic_key)

        valid_files = []
        dir_bytes = 0
        for f in files:
            fl = f.lower()
            if is_own_output_file(fl) or is_junk_file_name(fl):
                continue
            if fl.endswith((".json", ".xmp", ".srt")) or not is_valid_media_file(f):
                continue
            fp = os.path.join(root, f)
            try:
                sz = os.path.getsize(fp)
            except Exception:
                continue
            dir_bytes += sz
            valid_files.append((get_file_date_string(fp), f, sz))

        if not valid_files:
            continue

        valid_files.sort(key=lambda x: (x[0], _ord_ic_key(x[1])))
        rel = make_rel_path(root, clean_root)
        if rel == ".":
            rel = os.path.basename(clean_root)
        key = rel.replace("/", "_").replace("\\", "_")
        if not key:
            key = os.path.basename(clean_root)

        folder_stats.append({
            "key": key,
            "rel": rel,
            "count": len(valid_files),
            "bytes": dir_bytes,
            "oldest": valid_files[0][0],
            "newest": valid_files[-1][0]
        })

    return folder_stats


# ==============================================================================
# FORMÁTOVÁNÍ VÝSTUPŮ
# ==============================================================================
def format_file_size(bytes_val):
    if bytes_val >= 1073741824:
        return f"{bytes_val / 1073741824:.2f} GB"
    if bytes_val >= 1048576:
        return f"{bytes_val / 1048576:.2f} MB"
    if bytes_val >= 1024:
        return f"{bytes_val / 1024:.2f} KB"
    return f"{bytes_val} B"

def save_data_txt(output_filepath, all_records):
    today_dt = datetime.datetime.now().strftime("%d.%m.%Y %H:%M:%S")
    fname = os.path.basename(output_filepath)
    tab = "\t"

    lines = [
        f"// {fname}",
        f"// Autor: Jan BARTUNEK | Verze: {SCRIPT_VERSION} ({SCRIPT_DATE})",
        f"// Vygenerovano: {today_dt}",
        "// Sloupce: DATUM_CAS; \t NAZEV_SOUBORU; \t LATITUDE; \t LONGITUDE; \t VELIKOST_BAJTY; \t RELATIVNI_CESTA; \t STAV (G=GNSS unikat, S=bez GNSS, D=duplicita s GNSS); \t NADMORSKA_VYSKA",
        "window.MAPA_FOTEK_DATA = `",
        f"DATUM_CAS;{tab}NAZEV_SOUBORU;{tab}LATITUDE;{tab}LONGITUDE;{tab}VELIKOST_BAJTY;{tab}RELATIVNI_CESTA;{tab}STAV;{tab}NADMORSKA_VYSKA"
    ]

    for item in all_records:
        st = item.status or ("G" if item.has_gps else "S")
        if st == "S":
            lat_str = ""
            lon_str = ""
        else:
            # .NET Framework ToString("F6", InvariantCulture) - shodné zaokrouhlení jako BAT
            lat_str = fmt_net(item.latitude, 6)
            lon_str = fmt_net(item.longitude, 6)
        alt_str = fmt_net(item.altitude, 1) if item.altitude is not None else ""
        row = f"{item.date_taken_str};{tab}{item.file_name};{tab}{lat_str};{tab}{lon_str};{tab}{item.file_size_bytes};{tab}{item.relative_path};{tab}{st};{tab}{alt_str}"
        lines.append(row)

    lines.append("`;\n")

    content = "\n".join(lines)
    # Zápis v UTF-8 s BOM a konci řádků CRLF (StringBuilder.AppendLine v BAT)
    with open(output_filepath, "w", encoding="utf-8-sig", newline="\r\n", errors="replace") as f:
        f.write(content)

# Oddělovač tisíců a desetinná čárka pro "{0:N2}" -f v BAT. Operátor -f v PowerShellu
# používá jazykové nastavení Windows; pro české Windows (cs-CZ) je to nezlomitelná
# mezera (U+00A0) a čárka.
NET_N_GROUP_SEP = "\u00a0"
NET_N_DECIMAL_SEP = ","


def fmt_net_n2(value):
    """Emulace .NET Framework ToString("N2") pro cs-CZ (zaokrouhlení jako fmt_net)."""
    txt = fmt_net(value, 2)
    neg = txt.startswith("-")
    if neg:
        txt = txt[1:]
    int_part, _, frac = txt.partition(".")
    groups = []
    while len(int_part) > 3:
        groups.insert(0, int_part[-3:])
        int_part = int_part[:-3]
    groups.insert(0, int_part)
    out = NET_N_GROUP_SEP.join(groups) + NET_N_DECIMAL_SEP + frac
    return ("-" + out) if neg else out


def _u16len(text):
    """Délka řetězce v jednotkách UTF-16 (string.Length v .NET)."""
    return len(text.encode("utf-16-le")) // 2


def _pad_right(text, width):
    return text + " " * max(0, width - _u16len(text))


def _pad_left(text, width):
    return " " * max(0, width - _u16len(text)) + text


def save_stats_csv(output_filepath, folder_stats, is_en=False, target_dir=None):
    """Zápis CSV statistiky - přesně podle BAT (Volba [3]).
    Texty v CSV jsou v BAT vždy česky (nezávisle na jazyce menu), proto se is_en nepoužije."""
    stat_file_name = os.path.basename(output_filepath)
    timestamp_header = datetime.datetime.now().strftime("%d.%m.%Y %H:%M:%S")

    def gb(nbytes):
        return fmt_net_n2(nbytes / 1073741824) + " GB"

    # Celkové součty a globální extrémy (Ordinal porovnání)
    total_files = 0
    total_bytes = 0
    g_old = ""
    g_new = ""
    for st in folder_stats:
        total_files += st["count"]
        total_bytes += st["bytes"]
        o, n = st["oldest"], st["newest"]
        if o not in ("-", "") and (g_old == "" or o < g_old):
            g_old = o
        if n not in ("-", "") and (g_new == "" or n > g_new):
            g_new = n
    if g_old == "":
        g_old = "-"
    if g_new == "":
        g_new = "-"
    total_gb = gb(total_bytes)
    tot_files_s = str(total_files)
    tot_bytes_s = str(total_bytes)

    h2, h3, h4, h5, h6 = "NEJSTARSI_SOUBOR", "NEJNOVEJSI_SOUBOR", "POCET_SOUBORU", "VELIKOST_BAJTY", "VELIKOST_GB"

    def widths(h1, rows):
        w = [max(_u16len(h1), _u16len("CELKEM")), max(_u16len(h2), _u16len(g_old)),
             max(_u16len(h3), _u16len(g_new)), max(_u16len(h4), _u16len(tot_files_s)),
             max(_u16len(h5), _u16len(tot_bytes_s)), max(_u16len(h6), _u16len(total_gb))]
        for r in rows:
            for i, v in enumerate(r):
                w[i] = max(w[i], _u16len(v))
        return w

    def fmt_row(r, w):
        return "; ".join([_pad_right(r[0], w[0]), _pad_right(r[1], w[1]), _pad_right(r[2], w[2]),
                          _pad_left(r[3], w[3]), _pad_left(r[4], w[4]), _pad_left(r[5], w[5])])

    # ---------------- Tabulka 1: všechny složky se soubory ----------------
    h1 = "CESTA_SLOZKY"
    rows1 = [(st["key"], st["oldest"], st["newest"], str(st["count"]), str(st["bytes"]), gb(st["bytes"]))
             for st in folder_stats]
    w = widths(h1, rows1)
    lines = [
        f"// {stat_file_name}",
        f"// Autor: Jan BARTUNEK | Verze: {SCRIPT_VERSION} ({SCRIPT_DATE})",
        f"// Vygenerovano: {timestamp_header}",
        "// Sloupce: 1. CESTA_SLOZKY | 2. NEJSTARSI_SOUBOR | 3. NEJNOVEJSI_SOUBOR | 4. POCET_SOUBORU | 5. VELIKOST_BAJTY | 6. VELIKOST_GB",
        fmt_row((h1, h2, h3, h4, h5, h6), w),
    ]
    for r in rows1:
        lines.append(fmt_row(r, w))
    lines.append(fmt_row(("CELKEM", g_old, g_new, tot_files_s, tot_bytes_s, total_gb), w))

    # ------- Tabulka 2: hlavní složky 1. úrovně včetně všech podsložek -------
    groups = {}          # klíč bez ohledu na velikost písmen (OrdinalIgnoreCase)
    for st in folder_stats:
        rel = st["rel"].lstrip("\\/")
        m = re.search(r"[\\/]", rel)
        top = rel[:m.start()] if m else rel
        if not top.strip():
            base_dir = target_dir if target_dir else os.path.dirname(output_filepath)
            top = os.path.basename(os.path.abspath(base_dir).rstrip("\\/"))
            if not top.strip():
                top = "Koren"
        k = top.upper()
        g = groups.get(k)
        if g is None:
            g = groups[k] = {"name": top, "count": 0, "bytes": 0, "oldest": "", "newest": ""}
        g["count"] += st["count"]
        g["bytes"] += st["bytes"]
        o, n = st["oldest"], st["newest"]
        if o not in ("-", "") and (g["oldest"] == "" or o < g["oldest"]):
            g["oldest"] = o
        if n not in ("-", "") and (g["newest"] == "" or n > g["newest"]):
            g["newest"] = n
    top_list = sorted(groups.values(), key=lambda g: _ord_ic_key(g["name"]))
    for g in top_list:
        if g["oldest"] == "":
            g["oldest"] = "-"
        if g["newest"] == "":
            g["newest"] = "-"

    h1_2 = "HLAVNI_SLOZKA"
    rows2 = [(g["name"], g["oldest"], g["newest"], str(g["count"]), str(g["bytes"]), gb(g["bytes"]))
             for g in top_list]
    w2 = widths(h1_2, rows2)
    lines.append("")
    lines.append("")
    lines.append("// STATISTIKA HLAVNICH SLOZEK (1. UROVEN VCETNE VSECH PODSLOZEK)")
    lines.append("// Sloupce: 1. HLAVNI_SLOZKA | 2. NEJSTARSI_SOUBOR | 3. NEJNOVEJSI_SOUBOR | 4. POCET_SOUBORU | 5. VELIKOST_BAJTY | 6. VELIKOST_GB")
    lines.append(fmt_row((h1_2, h2, h3, h4, h5, h6), w2))
    for r in rows2:
        lines.append(fmt_row(r, w2))
    lines.append(fmt_row(("CELKEM", g_old, g_new, tot_files_s, tot_bytes_s, total_gb), w2))

    content = "\n".join(lines) + "\n"     # každý řádek ukončen CRLF (AppendLine)
    with open(output_filepath, "w", encoding="utf-8-sig", newline="\r\n", errors="replace") as f:
        f.write(content)


# ==============================================================================
# INTERAKTIVNÍ VÝBĚR PODSLOŽKY (Volba [2])
# ==============================================================================
def select_subfolder_interactive(root_dir, is_en=False):
    current = os.path.abspath(root_dir)
    root_base = current

    while True:
        subdirs = []
        try:
            for entry in os.scandir(current):
                if entry.is_dir() and not is_junk_dir_name(entry.name.lower()):
                    subdirs.append(entry.name)
            subdirs.sort(key=lambda s: s.upper())
        except Exception:
            pass

        print("\n" + "=" * 64)
        print("  SELECT TARGET FOLDER TO SCAN" if is_en else "  VYBER CILOVOU SLOZKU PRO SKEN")
        print(f"  Current location: {current}" if is_en else f"  Aktualni umisteni: {current}")
        print("-" * 64)

        for i, d in enumerate(subdirs):
            print(f"  [{i + 1:3d}] {d}")

        if not subdirs:
            print("  (no subfolders)" if is_en else "  (zadne podslozky)")

        print("")
        if is_en:
            print("  [B] one level up    [F/Enter] PROCESS THIS FOLDER    [K/Q] Back to main menu")
            choice = input("  Choice: ").strip()
        else:
            print("  [B] o urovni vys    [F/Enter] ZPRACOVAT TUTO SLOZKU    [K/Q] Zpet do hlavni nabidky")
            choice = input("  Volba: ").strip()

        if not choice or choice.upper() == "F":
            return current
        if choice.upper() in ("K", "Q"):
            return None
        if choice.upper() == "0":
            sys.exit(0)
        if choice.upper() == "B":
            parent = os.path.dirname(current)
            if len(parent) >= len(root_base):
                current = parent
            continue
        if choice.isdigit():
            idx = int(choice) - 1
            if 0 <= idx < len(subdirs):
                current = os.path.join(current, subdirs[idx])
                continue


# ==============================================================================
# HLAVNÍ NÍŽKOÚROVŇOVÝ KONZOLOVÝ PROGRAM
# ==============================================================================
def print_banner(is_en=False):
    print("=" * 64)
    if is_en:
        print("               PHOTO MAP - DATA UPDATE                          ")
        print("=" * 64)
        print(f" Author      : Jan BARTUNEK")
        print(f" Updated     : {SCRIPT_DATE} (Version {SCRIPT_VERSION}) [Python]")
        print(" Language    : CZ / [ EN ]    (press 'C' for Czech)")
    else:
        print("               MAPA FOTEK - AKTUALIZACE DAT                     ")
        print("=" * 64)
        print(f" Autor       : Jan BARTUNEK")
        print(f" Aktualizace : {SCRIPT_DATE} (Verze {SCRIPT_VERSION}) [Python]")
        print(" Jazyk       : [ CZ ] / EN    (stiskem 'E' pro anglictinu)")
    print("=" * 64)

def print_info(is_en=False):
    print("\n" + "=" * 64)
    if is_en:
        print("               PROGRAM INFORMATION AND GUIDE                    ")
        print("=" * 64)
        print(" ABOUT THE PROGRAM:")
        print("  Fast parallel photo & video archive processing for Mapa_Fotek.html.")
        print("  Supports Windows, Linux, macOS, and Android (Termux).")
        print("  Outputs identical 8-column data with altitude and status.")
    else:
        print("               INFORMACE O PROGRAMU A NAVOD                     ")
        print("=" * 64)
        print(" O PROGRAMU:")
        print("  Tento nastroj slouzi k rychlemu paralelnimu zpracovani archivu fotek")
        print("  a videi. Zpracuje VSECHNY soubory, nacte zemepisne souradnice (GNSS),")
        print("  nadmorskou vysku a kazdy zaznam oznaci STAVEM: G, S, D.")
        print("  Generuje vystupni soubory primo pro aplikaci 'Mapa_Fotek.html'.")
    print("=" * 64)
    input("  [Enter / K] " + ("Back to menu" if is_en else "Zpet do nabidky"))

def main():
    root_dir = os.path.dirname(os.path.abspath(__file__))
    current_lang = "cs"
    is_first_run = True

    while True:
        is_en = (current_lang == "en")
        print_banner(is_en)
        print("")

        if is_en:
            if is_first_run:
                print(" [1] Generate photo data (scan entire archive)  (Enter or auto in 3 s)")
            else:
                print(" [1] Generate photo data (scan entire archive)")
            print(" [2] Generate photo data (select specific subfolder)")
            print(" [3] Generate photo archive statistics")
            print("")
            print(" [I] Program information and guide")
            print("")
            print(" [0] Exit program")
        else:
            if is_first_run:
                print(" [1] Generovat data fotek (spustit sken celeho archivu)  (Enter nebo automaticky za 3 s)")
            else:
                print(" [1] Generovat data fotek (spustit sken celeho archivu)")
            print(" [2] Generovat data fotek (vybrat konkretni podslozku)")
            print(" [3] Generovat statistiku archivu fotek")
            print("")
            print(" [I] Informace o programu a navod")
            print("")
            print(" [0] Ukoncit program")
        print("")

        choice = None
        if is_first_run:
            # 3sekundový timeout pro automatický start [1] na prvním spuštění
            prompt_str = " Choice (auto in 3s): " if is_en else " Volba (automaticky za 3s): "
            print(prompt_str, end="", flush=True)
            try:
                # Windows podpora msvcrt pro stisk klávesy bez čekání
                if os.name == 'nt':
                    import msvcrt
                    start_t = time.time()
                    while time.time() - start_t < 3.0:
                        if msvcrt.kbhit():
                            ch = msvcrt.getch().decode("utf-8", errors="ignore")
                            if ch in ('\r', '\n', '1'): choice = '1'; break
                            elif ch == '2': choice = '2'; break
                            elif ch == '3': choice = '3'; break
                            elif ch.lower() == 'i': choice = 'I'; break
                            elif ch.lower() == 'c': current_lang = 'cs'; choice = 'RELOAD'; break
                            elif ch.lower() == 'e': current_lang = 'en'; choice = 'RELOAD'; break
                            elif ch == '0': sys.exit(0)
                        time.sleep(0.05)
                    if not choice:
                        choice = '1'
                        print("1")
                else:
                    # Linux / macOS / Android: jednoduchý input nebo automatika
                    choice = '1'
            except Exception:
                choice = '1'
            is_first_run = False
        else:
            prompt_str = " Choice: " if is_en else " Volba: "
            try:
                user_input = input(prompt_str).strip()
            except (EOFError, KeyboardInterrupt):
                sys.exit(0)
            if not user_input or user_input == '1': choice = '1'
            elif user_input == '2': choice = '2'
            elif user_input == '3': choice = '3'
            elif user_input.upper() == 'I': choice = 'I'
            elif user_input.lower() == 'c': current_lang = 'cs'; continue
            elif user_input.lower() == 'e': current_lang = 'en'; continue
            elif user_input == '0': sys.exit(0)

        if choice == 'RELOAD':
            continue

        if choice == 'I':
            print_info(is_en)
            continue

        if choice == '0':
            sys.exit(0)

        # Volba [3]: Statistika
        if choice == '3':
            print("")
            print(f" Archive folder: {root_dir}" if is_en else f" Slozka archivu: {root_dir}")
            print(" Analyzing folder structure and generating statistics..." if is_en else " Analyzuji strukturu slozek a generuji statistiku...")
            stats_list = generate_folder_statistics(root_dir)
            today_str = datetime.datetime.now().strftime("%Y%m%d")
            out_csv = os.path.join(root_dir, f"Mapa_Fotek_statistika_{today_str}.csv")
            save_stats_csv(out_csv, stats_list, is_en=is_en, target_dir=root_dir)
            print("")
            print("=" * 64)
            print(f" STATISTICS COMPLETED! Saved to: {out_csv}" if is_en else f" STATISTIKA DOKONCENA! Ulozeno do: {out_csv}")
            print("=" * 64)
            input(" [Enter] " + ("Back to menu" if is_en else "Zpet do nabidky"))
            continue

        # Volba [1] nebo [2]: Sken fotek
        target_scan_dir = root_dir
        picked_suffix = ""
        if choice == '2':
            chosen = select_subfolder_interactive(root_dir, is_en=is_en)
            if not chosen:
                continue
            target_scan_dir = chosen
            # Stejně jako BAT: segmenty relativní cesty, z konce odstraněny tečky/mezery
            rel_sub = os.path.relpath(chosen, root_dir).replace("\\", "/")
            rel_segs = [re.sub(r"[. ]+$", "", seg) for seg in rel_sub.split("/")]
            rel_segs = [seg for seg in rel_segs if seg]
            if rel_segs:
                picked_suffix = "_" + "_".join(rel_segs)

        print("")
        print(f" Photo folder: {target_scan_dir}" if is_en else f" Slozka fotek: {target_scan_dir}")
        print(" [1/3] Scanning folders and loading metadata..." if is_en else " [1/3] Skenuji slozky a nacitam metadata...")
        res = scan_archive(target_scan_dir)

        alt_count = sum(1 for r in res["all_records"] if r.altitude is not None)
        total_formatted = format_file_size(res["total_bytes"])

        print("")
        if is_en:
            print(f"   Total files in folders     : {res['total_files']:,}")
            print(f"   Files with GNSS (incl. D)  : {res['gps_before_dedup']:,}")
            print(f"   Unique for map (G)         : {len(res['gps_records']):,}  (duplicates D: {len(res['dup_records']):,}, without GNSS S: {len(res['no_gps_records']):,})")
            print(f"   With altitude              : {alt_count:,}")
            print(f"   Total file size            : {total_formatted}  (scan time: {res['elapsed_sec']:.1f} s)")
        else:
            print(f"   Celkem souboru ve slozkach : {res['total_files']:,}")
            print(f"   Souboru s GNSS (vc. D)     : {res['gps_before_dedup']:,}")
            print(f"   Unikatnich pro mapu (G)    : {len(res['gps_records']):,}  (duplicity D: {len(res['dup_records']):,}, bez GNSS S: {len(res['no_gps_records']):,})")
            print(f"   S nadmorskou vyskou        : {alt_count:,}")
            print(f"   Celkovy objem souboru      : {total_formatted}  (cas skenu: {res['elapsed_sec']:.1f} s)")

        today_str = datetime.datetime.now().strftime("%Y%m%d")
        out_txt_name = f"Mapa_Fotek_data_{today_str}{picked_suffix}.txt"
        out_txt_path = os.path.join(root_dir, out_txt_name)

        print("")
        print(f" [2/3] Saving data to: {out_txt_name}..." if is_en else f" [2/3] Ukladam data do: {out_txt_name}...")
        save_data_txt(out_txt_path, res["all_records"])

        print(" [3/3] Done!" if is_en else " [3/3] Hotovo!")
        print("")
        print("=" * 64)
        if is_en:
            print(" UPDATE COMPLETED SUCCESSFULLY!")
            print(f" Output file         : {out_txt_name}")
            print(f" Rows in output file : {len(res['all_records']):,}")
        else:
            print(" AKTUALIZACE DOKONCENA USPESNE!")
            print(f" Vystupni soubor            : {out_txt_name}")
            print(f" Radku ve vystupnim souboru : {len(res['all_records']):,}")
        print("=" * 64)
        print("")
        input(" [Enter] " + ("Back to menu" if is_en else "Zpet do nabidky"))

if __name__ == "__main__":
    main()
