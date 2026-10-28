#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Mapa Fotek - Aktualizace dat
Autor: Jan BARTUNEK
Verze: 2.21 (25.10.2026)
Multiplatformní verze (Windows, Linux, macOS, Android/Termux)
"""

import os
import sys
import re
import math
import time
import struct
import json
import datetime
from datetime import timezone
from multiprocessing import Pool, cpu_count

# Volitelná podpora Pillow (pokud je nainstalována, rozšiřuje podporu formátů)
try:
    from PIL import Image, ExifTags
    HAS_PILLOW = True
except ImportError:
    HAS_PILLOW = False

SCRIPT_VERSION = "2.21"
SCRIPT_DATE = "25.10.2026"

# Podporované přípony souborů
PHOTO_EXTS = {
    ".jpg", ".jpeg", ".heic", ".heif", ".avif", ".png", ".tif", ".tiff", ".bmp", ".gif", ".webp",
    ".dng", ".cr2", ".cr3", ".nef", ".arw", ".raf", ".orf", ".rw2", ".pef", ".srw"
}
VIDEO_EXTS = {
    ".mp4", ".mov", ".m4v", ".avi", ".mkv", ".wmv", ".3gp", ".flv", ".mts", ".m2ts", ".mpg", ".mpeg"
}
VIDEO_GPS_EXTS = {".mp4", ".mov", ".m4v", ".3gp"}
MEDIA_EXTS = PHOTO_EXTS | VIDEO_EXTS

JUNK_FILE_NAMES = {
    "thumbs.db", ".ds_store", "desktop.ini", ".picasa.ini", "picasa.ini",
    "ehthumbs.db", "ehthumbs_vista.db", "photothumb.db"
}
JUNK_DIR_NAMES = {
    "@eadir", "$recycle.bin", "system volume information", ".thumbnails",
    ".trashes", ".fseventsd", ".spotlight-v100", ".cache", "__pycache__"
}


# ==============================================================================
# TŘÍDA PRO ZÁZNAM MÉDIA
# ==============================================================================
def round_net(val, digits):
    """
    Kvantování s dělením po zaokrouhlení na celá čísla, odpovídá .NET Math.Round(double, int).
    """
    if val is None:
        return None
    factor = 10.0 ** digits
    return round(val * factor) / factor

class PhotoRecordItem:
    ALT_MIN = -500.0
    ALT_MAX = 15000.0

    def __init__(self, file_name="", date_taken_str="00000000_000000",
                 latitude=0.0, longitude=0.0, altitude=None,
                 relative_path="", file_size_bytes=0, has_gps=False,
                 status="", date_quality=0):
        self.file_name = file_name
        self.date_taken_str = date_taken_str
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude  # float or None
        self.relative_path = relative_path
        self.file_size_bytes = file_size_bytes
        self.has_gps = has_gps
        self.status = status      # "G", "D", "S"
        self.date_quality = date_quality  # 0=fallback, 1=UTC, 2=local exif

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
# POMOCNÉ FUNKCE PRO FILTROVÁNÍ A DATUM
# ==============================================================================
def is_own_output_file(name_lower):
    if name_lower.startswith("mapa_fotek_data_") and name_lower.endswith(".txt"):
        return True
    if name_lower.startswith("mapa_fotek_statistika_") and name_lower.endswith(".csv"):
        return True
    return False

def is_junk_file_name(name_lower):
    if name_lower in JUNK_FILE_NAMES:
        return True
    if name_lower.endswith(".tmp") or name_lower.endswith(".thm"):
        return True
    if name_lower.endswith(".bat") or name_lower.endswith(".ps1") or name_lower.endswith(".py"):
        return True
    return False

def is_junk_dir_name(dir_lower):
    return dir_lower in JUNK_DIR_NAMES

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

def parse_filename_date(filename):
    if not filename:
        return None
    name = os.path.splitext(filename)[0]

    for m in FN_DATETIME_REGEX.finditer(name):
        if not fn_year_ok(m.group(1)): continue
        try:
            dt = datetime.datetime(int(m.group(1)), int(m.group(2)), int(m.group(3)),
                                   int(m.group(4)), int(m.group(5)), int(m.group(6)))
            return dt.strftime("%Y%m%d_%H%M%S")
        except ValueError:
            pass

    for m in FN_DATE_REGEX.finditer(name):
        if not fn_year_ok(m.group(1)): continue
        try:
            dt = datetime.datetime(int(m.group(1)), int(m.group(3)), int(m.group(4)))
            return dt.strftime("%Y%m%d_000000")
        except ValueError:
            pass

    counter_pos = {cm.start(1) for cm in FN_COUNTER_REGEX.finditer(name)}

    for m in FN_YEAR_MONTH_REGEX.finditer(name):
        if m.start(1) in counter_pos or not fn_year_ok(m.group(1)): continue
        return f"{m.group(1)}{m.group(2)}01_000000"

    for m in FN_YEAR_REGEX.finditer(name):
        if m.start(1) in counter_pos or not fn_year_ok(m.group(1)): continue
        return f"{m.group(1)}0101_000000"

    return None

def parse_filename_datetime(filename):
    return parse_filename_date(filename)

def is_valid_year(year):
    return 1900 <= year <= 2100

ISO_DATE_REGEX = re.compile(
    r'^(\d{4})[-:](\d{2})[-:](\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:[.,]\d+)?)?\s*(Z|[+-]\d{2}(?::?\d{2})?)?$',
    re.IGNORECASE
)

def parse_iso_wall_clock(s):
    if not s or not isinstance(s, str):
        return None
    s = s.strip()
    m = ISO_DATE_REGEX.match(s)
    if not m:
        return None
    try:
        y = int(m.group(1))
        mo = int(m.group(2))
        d = int(m.group(3))
        h = int(m.group(4))
        mi = int(m.group(5))
        sec = int(float(m.group(6))) if m.group(6) else 0
        if not is_valid_year(y):
            return None
        dt = datetime.datetime(y, mo, d, h, mi, sec)
        tz = m.group(7)
        if tz and tz.upper() == 'Z':
            dt = dt.replace(tzinfo=timezone.utc).astimezone().replace(tzinfo=None)
            if not is_valid_year(dt.year):
                return None
        return dt.strftime("%Y%m%d_%H%M%S")
    except Exception:
        return None

KNOWN_DATE_FORMATS = (
    "%Y:%m:%d %H:%M:%S",
    "%Y-%m-%d %H:%M:%S",
    "%Y/%m/%d %H:%M:%S",
    "%Y%m%d_%H%M%S",
    "%Y-%m-%dT%H:%M:%S",
    "%Y:%m:%d%T%H:%M:%S",
    "%Y-%m-%d",
    "%Y:%m:%d",
    "%Y%m%d",
    "%d.%m.%Y %H:%M:%S",
    "%d.%m.%Y %H:%M:%S",
    "%d.%m.%Y",
    "%m/%d/%Y %H:%M:%S",
    "%m/%d/%Y",
)

def parse_date_string(s):
    if not s or not isinstance(s, str):
        return None
    s = s.strip().strip('\0').strip()
    if len(s) < 10 or s.startswith("0000"):
        return None
    iso = parse_iso_wall_clock(s)
    if iso:
        return iso
    for fmt in KNOWN_DATE_FORMATS:
        try:
            dt = datetime.datetime.strptime(s, fmt)
            if is_valid_year(dt.year):
                return dt.strftime("%Y%m%d_%H%M%S")
        except Exception:
            pass
    if len(s) > 19:
        s19 = s[:19]
        for fmt in KNOWN_DATE_FORMATS:
            try:
                dt = datetime.datetime.strptime(s19, fmt)
                if is_valid_year(dt.year):
                    return dt.strftime("%Y%m%d_%H%M%S")
            except Exception:
                pass
    return None

def parse_datetime_to_full_str(date_taken, file_name, file_date):
    if date_taken:
        p_dt = parse_date_string(date_taken)
        if p_dt:
            return p_dt
    from_name = parse_filename_datetime(file_name)
    if from_name and not from_name.startswith("0000"):
        return from_name
    if isinstance(file_date, datetime.datetime):
        return file_date.strftime("%Y%m%d_%H%M%S")
    elif isinstance(file_date, (int, float)) and file_date > 0:
        try:
            return datetime.datetime.fromtimestamp(file_date).strftime("%Y%m%d_%H%M%S")
        except Exception:
            pass
    return "00000000_000000"

def get_file_mtime_str(filepath):
    try:
        mtime = os.path.getmtime(filepath)
        dt = datetime.datetime.fromtimestamp(mtime)
        return dt.strftime("%Y%m%d_%H%M%S")
    except Exception:
        return "00000000_000000"

def get_file_date_string(filepath):
    fname = os.path.basename(filepath)
    ext = os.path.splitext(fname)[1].lower()
    if ext in PHOTO_EXTS:
        date_str, _, _, _, _, dq = read_photo_metadata(filepath)
        if date_str and dq >= 2:
            return date_str
    elif ext in VIDEO_EXTS:
        if ext in VIDEO_GPS_EXTS:
            date_str, _, _, _, _, dq = read_video_metadata(filepath)
            if date_str and dq >= 1:
                return date_str

    fn_date = parse_filename_date(fname)
    if fn_date:
        return fn_date
    return get_file_mtime_str(filepath)


# ==============================================================================
# EXIF PARSER (Čistý Python pro JPEG, TIFF + Pillow nadstavba)
# ==============================================================================
def _decode_rational(num, den):
    if den == 0:
        return 0.0
    return float(num) / float(den)

def decode_alt_ref(ref_val):
    if ref_val is None:
        return 0
    if isinstance(ref_val, (bytes, bytearray)):
        if len(ref_val) == 0:
            return 0
        b0 = ref_val[0]
        return 1 if b0 in (1, ord('1')) else 0
    s = str(ref_val).strip()
    if s == "1":
        return 1
    try:
        return 1 if int(ref_val) == 1 else 0
    except Exception:
        return 0

def decode_alt_val(val):
    if val is None:
        return None
    try:
        if isinstance(val, (tuple, list)):
            if len(val) >= 2 and val[1] != 0:
                return float(val[0]) / float(val[1])
            return float(val[0])
        return float(val)
    except Exception:
        return None

def parse_jpeg_exif_pure(filepath):
    """
    Rychlý nativní parser JPEG APP1 (EXIF / XMP) bez nutnosti instalace knihoven.
    """
    date_str = None
    lat = None
    lon = None
    alt = None

    try:
        with open(filepath, "rb") as f:
            header = f.read(2)
            if header != b"\xff\xd8":
                return None, None, None, None

            while True:
                marker_data = f.read(4)
                if len(marker_data) < 4 or marker_data[0] != 0xff:
                    break
                marker = marker_data[1]
                length = struct.unpack(">H", marker_data[2:4])[0]
                if length < 2:
                    break
                data_len = length - 2

                if marker == 0xe1:  # APP1 (Exif or XMP)
                    app1_data = f.read(data_len)
                    if app1_data.startswith(b"Exif\x00\x00"):
                        tiff_data = app1_data[6:]
                        d, la, lo, al = parse_tiff_exif_bytes(tiff_data)
                        if d and not date_str: date_str = d
                        if la is not None and lat is None: lat = la; lon = lo
                        if al is not None and alt is None: alt = al
                    elif app1_data.startswith(b"http://ns.adobe.com/xap/1.0/\x00"):
                        xmp_text = app1_data[29:].decode("utf-8", errors="ignore")
                        xd, xla, xlo, xal = parse_xmp_text(xmp_text)
                        if xd and not date_str: date_str = xd
                        if xla is not None and lat is None: lat = xla; lon = xlo
                        if xal is not None and alt is None: alt = xal
                elif marker in (0xda, 0xd9):  # SOS or EOI
                    break
                else:
                    f.seek(data_len, os.SEEK_CUR)
    except Exception:
        pass

    return date_str, lat, lon, alt

def parse_tiff_exif_bytes(tiff_bytes):
    date_str = None
    lat = None
    lon = None
    alt = None

    if len(tiff_bytes) < 8:
        return None, None, None, None

    order_marker = tiff_bytes[:2]
    if order_marker == b"II":
        endian = "<"
    elif order_marker == b"MM":
        endian = ">"
    else:
        return None, None, None, None

    magic = struct.unpack(endian + "H", tiff_bytes[2:4])[0]
    if magic != 42:
        return None, None, None, None

    ifd0_offset = struct.unpack(endian + "I", tiff_bytes[4:8])[0]
    if ifd0_offset >= len(tiff_bytes):
        return None, None, None, None

    def read_ifd(offset):
        entries = {}
        if offset + 2 > len(tiff_bytes):
            return entries
        num_tags = struct.unpack(endian + "H", tiff_bytes[offset:offset+2])[0]
        p = offset + 2
        for _ in range(num_tags):
            if p + 12 > len(tiff_bytes):
                break
            tag, ftype, count, val_or_off = struct.unpack(endian + "HHI I", tiff_bytes[p:p+12])
            entries[tag] = (ftype, count, val_or_off)
            p += 12
        return entries

    def get_value(ftype, count, val_or_off):
        if ftype == 1:  # BYTE
            raw_bytes = struct.pack(endian + "I", val_or_off)
            return raw_bytes[0]
        elif ftype == 2:  # ASCII
            if count <= 4:
                s = struct.pack(endian + "I", val_or_off)[:count]
            else:
                s = tiff_bytes[val_or_off:val_or_off+count]
            return s.decode("utf-8", errors="ignore").rstrip("\x00").strip()
        elif ftype == 3:  # SHORT
            raw_bytes = struct.pack(endian + "I", val_or_off)
            return struct.unpack(endian + "H", raw_bytes[:2])[0]
        elif ftype == 4:  # LONG
            return val_or_off
        elif ftype == 5:  # RATIONAL (two LONGs)
            if val_or_off + 8 <= len(tiff_bytes):
                num, den = struct.unpack(endian + "II", tiff_bytes[val_or_off:val_or_off+8])
                return (num, den)
        return None

    ifd0 = read_ifd(ifd0_offset)

    # Exif SubIFD (cteme pouze DateTimeOriginal a DateTimeDigitized, nikoli tag 306/DateTime)
    if 0x8769 in ifd0:
        exif_off = ifd0[0x8769][2]
        exif_ifd = read_ifd(exif_off)
        for dtag in (0x9003, 0x9004):  # DateTimeOriginal, DateTimeDigitized
            if dtag in exif_ifd:
                val = get_value(*exif_ifd[dtag])
                if isinstance(val, str) and len(val) >= 10 and not val.startswith("0000"):
                    p_dt = parse_date_string(val)
                    if p_dt:
                        date_str = p_dt
                        break

    # GPS SubIFD
    if 0x8825 in ifd0:
        gps_off = ifd0[0x8825][2]
        gps_ifd = read_ifd(gps_off)

        lat_ref = get_value(*gps_ifd[1]) if 1 in gps_ifd else "N"
        lon_ref = get_value(*gps_ifd[3]) if 3 in gps_ifd else "E"

        if 2 in gps_ifd and 4 in gps_ifd:
            lat_off = gps_ifd[2][2]
            lon_off = gps_ifd[4][2]
            if lat_off + 24 <= len(tiff_bytes) and lon_off + 24 <= len(tiff_bytes):
                lat_d = _decode_rational(*struct.unpack(endian + "II", tiff_bytes[lat_off:lat_off+8]))
                lat_m = _decode_rational(*struct.unpack(endian + "II", tiff_bytes[lat_off+8:lat_off+16]))
                lat_s = _decode_rational(*struct.unpack(endian + "II", tiff_bytes[lat_off+16:lat_off+24]))
                dec_lat = lat_d + (lat_m / 60.0) + (lat_s / 3600.0)
                if str(lat_ref).strip().upper() == "S":
                    dec_lat = -dec_lat

                lon_d = _decode_rational(*struct.unpack(endian + "II", tiff_bytes[lon_off:lon_off+8]))
                lon_m = _decode_rational(*struct.unpack(endian + "II", tiff_bytes[lon_off+8:lon_off+16]))
                lon_s = _decode_rational(*struct.unpack(endian + "II", tiff_bytes[lon_off+16:lon_off+24]))
                dec_lon = lon_d + (lon_m / 60.0) + (lon_s / 3600.0)
                if str(lon_ref).strip().upper() == "W":
                    dec_lon = -dec_lon

                if abs(dec_lat) <= 90.0 and abs(dec_lon) <= 180.0 and not (abs(dec_lat) < 0.0001 and abs(dec_lon) < 0.0001):
                    lat = round_net(dec_lat, 6)
                    lon = round_net(dec_lon, 6)

        # Nadmořská výška (GPSAltitude = tag 6, GPSAltitudeRef = tag 5)
        if 6 in gps_ifd:
            alt_rat = get_value(*gps_ifd[6])
            raw_alt = None
            if isinstance(alt_rat, tuple):
                raw_alt = _decode_rational(*alt_rat)
            elif alt_rat is not None:
                raw_alt = decode_alt_val(alt_rat)
            if raw_alt is not None:
                alt_ref = 0
                if 5 in gps_ifd:
                    ref_val = get_value(*gps_ifd[5])
                    alt_ref = decode_alt_ref(ref_val)
                signed_alt = -abs(raw_alt) if alt_ref == 1 else raw_alt
                alt = PhotoRecordItem.valid_altitude(signed_alt)

    return date_str, lat, lon, alt


def parse_heic_exif(filepath):
    """
    Rychlý nativní parser EXIF pro HEIC/HEIF bez nutnosti instalace knihoven.
    Prohledá prvních 4 MB souboru na TIFF hlavičku (II*\\0 nebo MM\\0*).
    """
    try:
        with open(filepath, "rb") as f:
            chunk = f.read(4 * 1024 * 1024)
            for sig in (b"II\x2a\x00", b"MM\x00\x2a"):
                idx = 0
                while True:
                    idx = chunk.find(sig, idx)
                    if idx < 0:
                        break
                    res = parse_tiff_exif_bytes(chunk[idx:])
                    if res and (res[0] or res[1] is not None):
                        return res
                    idx += 4
    except Exception:
        pass
    return None, None, None, None


def parse_png_metadata_pure(filepath):
    date_str, lat, lon, alt = None, None, None, None
    try:
        with open(filepath, 'rb') as f:
            sig = f.read(8)
            if sig != b'\x89PNG\r\n\x1a\n':
                return None, None, None, None
            while True:
                hdr = f.read(8)
                if len(hdr) < 8: break
                length, ctype = struct.unpack('>I4s', hdr)
                data = f.read(length)
                f.read(4)  # CRC
                if ctype == b'eXIf':
                    d, la, lo, al = parse_tiff_exif_bytes(data)
                    if d and not date_str: date_str = d
                    if la is not None and lat is None: lat, lon = la, lo
                    if al is not None and alt is None: alt = al
                elif ctype == b'iTXt':
                    if b'XML:com.adobe.xmp' in data:
                        idx = data.find(b'<?xpacket')
                        if idx < 0: idx = data.find(b'<x:xmpmeta')
                        if idx >= 0:
                            xmp_text = data[idx:].decode('utf-8', errors='ignore')
                            d, la, lo, al = parse_xmp_text(xmp_text)
                            if d and not date_str: date_str = d
                            if la is not None and lat is None: lat, lon = la, lo
                            if al is not None and alt is None: alt = al
                elif ctype == b'IEND':
                    break
    except Exception:
        pass
    return date_str, lat, lon, alt


def read_photo_metadata(filepath):
    """
    Univerzální načtení metadat fotky (Pillow s fallbackem na čistý Python).
    """
    ext = os.path.splitext(filepath)[1].lower()
    date_str = None
    lat = None
    lon = None
    alt = None
    date_quality = 0

    # 1. Zkusit Pillow, pokud je dostupný
    if HAS_PILLOW:
        try:
            with Image.open(filepath) as img:
                exif = img.getexif()
                if exif:
                    # Datum z Exif SubIFD nebo IFD0
                    exif_sub = None
                    try:
                        exif_sub = exif.get_ifd(ExifTags.IFD.Exif)
                    except Exception:
                        pass

                    raw_date = None
                    if exif_sub:
                        raw_date = exif_sub.get(36867) or exif_sub.get(36868)  # DateTimeOriginal, DateTimeDigitized

                    if raw_date and isinstance(raw_date, str):
                        p_dt = parse_date_string(raw_date)
                        if p_dt:
                            date_str = p_dt
                            date_quality = 2

                    # GPS z GPS IFD
                    gps_info = None
                    try:
                        gps_info = exif.get_ifd(ExifTags.IFD.GPSInfo)
                    except Exception:
                        pass

                    if gps_info:
                        lat_ref = gps_info.get(1, "N")
                        lat_val = gps_info.get(2)
                        lon_ref = gps_info.get(3, "E")
                        lon_val = gps_info.get(4)

                        if lat_val and lon_val:
                            def to_deg(v):
                                try:
                                    d = float(v[0])
                                    m = float(v[1])
                                    s = float(v[2])
                                    return d + (m / 60.0) + (s / 3600.0)
                                except Exception:
                                    return None

                            d_lat = to_deg(lat_val)
                            d_lon = to_deg(lon_val)
                            if d_lat is not None and d_lon is not None:
                                if str(lat_ref).strip().upper() == "S": d_lat = -d_lat
                                if str(lon_ref).strip().upper() == "W": d_lon = -d_lon
                                if abs(d_lat) <= 90.0 and abs(d_lon) <= 180.0 and not (abs(d_lat) < 0.0001 and abs(d_lon) < 0.0001):
                                    lat = round_net(d_lat, 6)
                                    lon = round_net(d_lon, 6)

                        # Nadmořská výška (tag 6, ref 5)
                        alt_val = gps_info.get(6)
                        if alt_val is not None:
                            try:
                                raw_alt = decode_alt_val(alt_val)
                                if raw_alt is not None:
                                    alt_ref = decode_alt_ref(gps_info.get(5, 0))
                                    signed_alt = -abs(raw_alt) if alt_ref == 1 else raw_alt
                                    alt = PhotoRecordItem.valid_altitude(signed_alt)
                            except Exception:
                                pass

                # XMP v PNG/TIFF info slovníku
                if (lat is None or date_str is None) and hasattr(img, "info"):
                    for xk in ("XML:com.adobe.xmp", "xmp"):
                        if xk in img.info and isinstance(img.info[xk], (str, bytes)):
                            xtxt = img.info[xk]
                            if isinstance(xtxt, bytes):
                                xtxt = xtxt.decode("utf-8", errors="ignore")
                            xd, xla, xlo, xal = parse_xmp_text(xtxt)
                            if xd and not date_str: date_str = xd; date_quality = 2
                            if xla is not None and lat is None: lat = xla; lon = xlo
                            if xal is not None and alt is None: alt = xal
                            break
        except Exception:
            pass

    # 2. Fallback pro JPEG/TIFF/DNG/PNG/HEIC v čistém Pythonu bez Pillow
    if lat is None or date_str is None:
        if ext in {".jpg", ".jpeg", ".tif", ".tiff", ".dng"}:
            p_date, p_lat, p_lon, p_alt = parse_jpeg_exif_pure(filepath)
            if p_date and not date_str:
                date_str = p_date
                date_quality = 2
            if p_lat is not None and lat is None:
                lat = p_lat
                lon = p_lon
            if p_alt is not None and alt is None:
                alt = p_alt
        elif ext == ".png":
            p_date, p_lat, p_lon, p_alt = parse_png_metadata_pure(filepath)
            if p_date and not date_str:
                date_str = p_date
                date_quality = 2
            if p_lat is not None and lat is None:
                lat = p_lat
                lon = p_lon
            if p_alt is not None and alt is None:
                alt = p_alt
        elif ext in {".heic", ".heif", ".avif"}:
            h_date, h_lat, h_lon, h_alt = parse_heic_exif(filepath)
            if h_date and not date_str:
                date_str = h_date
                date_quality = 2
            if h_lat is not None and lat is None:
                lat = h_lat
                lon = h_lon
            if h_alt is not None and alt is None:
                alt = h_alt

    # 3. Fallback data: název souboru -> čas změny souboru
    if not date_str:
        try:
            mtime = os.path.getmtime(filepath)
        except Exception:
            mtime = 0
        date_str = parse_datetime_to_full_str(None, os.path.basename(filepath), mtime)
        date_quality = 0

    has_gps = (lat is not None and lon is not None)
    return date_str, (lat or 0.0), (lon or 0.0), alt, has_gps, date_quality


# ==============================================================================
# VIDEO PARSER (MP4, MOV, M4V, 3GP - QuickTime ISO 6709 a mvhd)
# ==============================================================================
ISO6709_REGEX = re.compile(r'([+-]\d{1,3}(?:\.\d+)?)([+-]\d{1,3}(?:\.\d+)?)([+-]\d{1,5}(?:\.\d+)?)?')

def parse_iso6709(s):
    if not s or not isinstance(s, str):
        return None, None, None
    m = ISO6709_REGEX.search(s)
    if not m:
        return None, None, None
    try:
        lat = float(m.group(1))
        lon = float(m.group(2))
        if abs(lat) > 90.0 or abs(lon) > 180.0 or (abs(lat) < 0.0001 and abs(lon) < 0.0001):
            return None, None, None
        alt = None
        if m.group(3):
            alt = PhotoRecordItem.valid_altitude(float(m.group(3)))
        return round_net(lat, 6), round_net(lon, 6), alt
    except Exception:
        return None, None, None

def read_video_metadata(filepath):
    """
    Rychlý binární rozbor 'moov' atomu MP4/MOV pro datum a GPS souřadnice.
    """
    date_str = None
    lat = None
    lon = None
    alt = None
    date_quality = 0

    try:
        with open(filepath, "rb") as f:
            moov_bytes = None
            while True:
                hdr = f.read(8)
                if len(hdr) < 8:
                    break
                box_size, box_type = struct.unpack(">I4s", hdr)
                if box_size == 1:  # 64-bit large box
                    hdr_ext = f.read(8)
                    if len(hdr_ext) < 8: break
                    box_size = struct.unpack(">Q", hdr_ext)[0]
                    content_size = box_size - 16
                else:
                    content_size = box_size - 8

                if box_type == b"moov":
                    read_len = min(content_size, 64 * 1024 * 1024)
                    moov_bytes = f.read(read_len)
                    break
                else:
                    f.seek(content_size, os.SEEK_CUR)

            if moov_bytes:
                # 1. Hledání Apple keys (creationdate, location.ISO6709)
                def find_apple_key(wanted):
                    try:
                        p = 0
                        while p + 8 <= len(moov_bytes):
                            if moov_bytes[p+4:p+8] == b"keys":
                                box_len = struct.unpack(">I", moov_bytes[p:p+4])[0]
                                count = struct.unpack(">I", moov_bytes[p+8:p+12])[0]
                                kp = p + 12
                                wanted_idx = -1
                                for ki in range(1, count + 1):
                                    if kp + 8 > len(moov_bytes): break
                                    k_size = struct.unpack(">I", moov_bytes[kp:kp+4])[0]
                                    k_name = moov_bytes[kp+8:kp+k_size].decode("utf-8", errors="ignore")
                                    if k_name == wanted:
                                        wanted_idx = ki
                                        break
                                    kp += k_size

                                if wanted_idx > 0:
                                    # Hledat ilst atom
                                    ip = p + box_len
                                    while ip + 8 <= len(moov_bytes):
                                        if moov_bytes[ip+4:ip+8] == b"ilst":
                                            ilst_end = ip + struct.unpack(">I", moov_bytes[ip:ip+4])[0]
                                            qp = ip + 8
                                            while qp + 8 <= ilst_end:
                                                item_sz, item_idx = struct.unpack(">II", moov_bytes[qp:qp+8])
                                                if item_idx == wanted_idx:
                                                    dp = qp + 8
                                                    while dp + 8 <= qp + item_sz:
                                                        d_sz, d_type = struct.unpack(">I4s", moov_bytes[dp:dp+8])
                                                        if d_type == b"data":
                                                            val_bytes = moov_bytes[dp+16:dp+d_sz]
                                                            return val_bytes.decode("utf-8", errors="ignore").strip()
                                                        dp += d_sz
                                                qp += item_sz
                                            break
                                        ip += 1
                                break
                            p += 1
                    except Exception:
                        pass
                    return None

                # Apple creationdate
                apple_date = find_apple_key("com.apple.quicktime.creationdate")
                if apple_date:
                    p_dt = parse_date_string(apple_date)
                    if p_dt:
                        date_str = p_dt
                        date_quality = 2

                # Apple location ISO 6709
                apple_loc = find_apple_key("com.apple.quicktime.location.ISO6709")
                if apple_loc:
                    la, lo, al = parse_iso6709(apple_loc)
                    if la is not None:
                        lat, lon, alt = la, lo, al

                # 2. Hledání QuickTime ©xyz atomu (Android, DJI, kamery)
                if lat is None:
                    xyz_idx = 0
                    while True:
                        xyz_idx = moov_bytes.find(b"\xa9xyz", xyz_idx)
                        if xyz_idx < 0:
                            break
                        take = min(160, len(moov_bytes) - (xyz_idx + 4))
                        if take > 0:
                            chunk = moov_bytes[xyz_idx + 4 : xyz_idx + 4 + take].decode("ascii", errors="ignore")
                            la, lo, al = parse_iso6709(chunk)
                            if la is not None:
                                lat, lon, alt = la, lo, al
                                break
                        xyz_idx += 4

                # 3. Hledání loci boxu (3GPP location)
                if lat is None:
                    loci_idx = moov_bytes.find(b"loci")
                    if loci_idx >= 4:
                        box_start = loci_idx - 4
                        box_sz = struct.unpack(">I", moov_bytes[box_start:box_start+4])[0]
                        if box_sz >= 22 and box_start + box_sz <= len(moov_bytes):
                            try:
                                fixed_lat = struct.unpack(">i", moov_bytes[box_start+14:box_start+18])[0] / 65536.0
                                fixed_lon = struct.unpack(">i", moov_bytes[box_start+18:box_start+22])[0] / 65536.0
                                fixed_alt = None
                                if box_sz >= 26:
                                    fixed_alt = PhotoRecordItem.valid_altitude(struct.unpack(">i", moov_bytes[box_start+22:box_start+26])[0] / 65536.0)
                                if abs(fixed_lat) <= 90.0 and abs(fixed_lon) <= 180.0 and not (abs(fixed_lat) < 0.0001 and abs(fixed_lon) < 0.0001):
                                    lat = round_net(fixed_lat, 6)
                                    lon = round_net(fixed_lon, 6)
                                    alt = fixed_alt
                            except Exception:
                                pass

                # 4. mvhd atom datum (sekundy od 1904-01-01 UTC)
                if not date_str:
                    mvhd_idx = moov_bytes.find(b"mvhd")
                    if mvhd_idx >= 4:
                        box_start = mvhd_idx - 4
                        version = moov_bytes[box_start+8]
                        if version == 0:
                            creation_time = struct.unpack(">I", moov_bytes[box_start+12:box_start+16])[0]
                        else:
                            creation_time = struct.unpack(">Q", moov_bytes[box_start+12:box_start+20])[0]

                        # QuickTime epoch: 1904-01-01
                        if creation_time > 2082844800:  # po roce 1970
                            epoch_1970 = creation_time - 2082844800
                            raw_dt = datetime.datetime(1904, 1, 1) + datetime.timedelta(seconds=creation_time)
                            fn_dt_str = parse_filename_datetime(os.path.basename(filepath))
                            fn_dt = None
                            if fn_dt_str and not fn_dt_str.startswith("0000"):
                                try:
                                    fn_dt = datetime.datetime.strptime(fn_dt_str, "%Y%m%d_%H%M%S")
                                except Exception:
                                    pass
                            if fn_dt and abs((fn_dt - raw_dt).total_seconds()) <= 300:
                                # Kamera zapsala mistni cas
                                date_str = raw_dt.strftime("%Y%m%d_%H%M%S")
                                date_quality = 2
                            else:
                                dt = datetime.datetime.fromtimestamp(epoch_1970)
                                if is_valid_year(dt.year):
                                    date_str = dt.strftime("%Y%m%d_%H%M%S")
                                    date_quality = 1
    except Exception:
        pass

    # Fallback
    if not date_str:
        try:
            mtime = os.path.getmtime(filepath)
        except Exception:
            mtime = 0
        date_str = parse_datetime_to_full_str(None, os.path.basename(filepath), mtime)
        date_quality = 0

    has_gps = (lat is not None and lon is not None)
    return date_str, (lat or 0.0), (lon or 0.0), alt, has_gps, date_quality


# ==============================================================================
# SIDECAR PARSERY (Google Photos JSON, Adobe XMP, DJI SRT)
# ==============================================================================
def parse_google_json(json_path):
    """
    Načte Google Photos .json sidecar soubor.
    """
    try:
        with open(json_path, "r", encoding="utf-8", errors="ignore") as f:
            data = json.load(f)

        lat = 0.0
        lon = 0.0
        alt = None
        has_gps = False

        # geoData / geoDataExif
        for gk in ("geoData", "geoDataExif"):
            if gk in data and isinstance(data[gk], dict):
                g = data[gk]
                g_lat = float(g.get("latitude", 0.0))
                g_lon = float(g.get("longitude", 0.0))
                if abs(g_lat) <= 90.0 and abs(g_lon) <= 180.0 and not (abs(g_lat) < 0.0001 and abs(g_lon) < 0.0001):
                    lat = g_lat
                    lon = g_lon
                    has_gps = True
                    if "altitude" in g:
                        alt = PhotoRecordItem.valid_altitude(float(g["altitude"]))
                    break

        # Datum z photoTakenTime
        date_str = "00000000_000000"
        date_quality = 0
        if "photoTakenTime" in data and isinstance(data["photoTakenTime"], dict):
            ts = data["photoTakenTime"].get("timestamp")
            if ts:
                ts_int = int(ts)
                # Normalizace na sekundy (pokud je v ms nebo us)
                if ts_int > 1000000000000000:
                    ts_int //= 1000000
                elif ts_int > 1000000000000:
                    ts_int //= 1000
                dt = datetime.datetime.fromtimestamp(ts_int)
                date_str = dt.strftime("%Y%m%d_%H%M%S")
                date_quality = 1

        title = data.get("title", "")
        return {
            "title": title,
            "has_gps": has_gps,
            "latitude": round_net(lat, 6),
            "longitude": round_net(lon, 6),
            "altitude": alt,
            "date_taken_str": date_str,
            "date_quality": date_quality
        }
    except Exception:
        return None

def parse_xmp_coordinate(val):
    if not val or not isinstance(val, str):
        return None
    val = val.strip()
    is_neg = val.upper().endswith(('S', 'W'))
    val = re.sub(r'[NSEWnsew]$', '', val).strip()
    parts = re.split(r'[, ;]+', val)
    try:
        if len(parts) == 1:
            d = float(parts[0].replace(',', '.'))
            return -d if is_neg else d
        elif len(parts) == 2:
            d = float(parts[0].replace(',', '.'))
            m = float(parts[1].replace(',', '.'))
            dec = d + (m / 60.0)
            return -dec if is_neg else dec
        elif len(parts) >= 3:
            d = float(parts[0].replace(',', '.'))
            m = float(parts[1].replace(',', '.'))
            s = float(parts[2].replace(',', '.'))
            dec = d + (m / 60.0) + (s / 3600.0)
            return -dec if is_neg else dec
    except Exception:
        pass
    return None

def parse_xmp_text(content):
    date_str = None
    lat = None
    lon = None
    alt = None

    # Datum (poradi: DateTimeOriginal, DateCreated, CreateDate; hodnota s casem ma prednost pred samotnym datem)
    xmp_date_val = None
    for dKey in ('DateTimeOriginal', 'DateCreated', 'CreateDate'):
        for md in re.finditer(r'(?<![A-Za-z])' + dKey + r'\s*(?:>|=\s*["\'])\s*([^<"\']+)', content, re.IGNORECASE):
            v = md.group(1).strip()
            if len(v) < 4: continue
            if xmp_date_val is None: xmp_date_val = v
            if ":" in v and re.search(r'\d[T ]\d', v):
                xmp_date_val = v
                break
        if xmp_date_val and ":" in xmp_date_val and re.search(r'\d[T ]\d', xmp_date_val):
            break

    if xmp_date_val and ":" in xmp_date_val and re.search(r'\d[T ]\d', xmp_date_val):
        p_dt = parse_date_string(xmp_date_val)
        if p_dt:
            date_str = p_dt

    # Souřadnice
    def parse_coord(tag):
        m = re.search(rf'{tag}\s*(?:>|=["\'])\s*([^<"\']+)', content, re.IGNORECASE)
        if m:
            return parse_xmp_coordinate(m.group(1))
        return None

    la = parse_coord("GPSLatitude")
    lo = parse_coord("GPSLongitude")
    if la is not None and lo is not None:
        if abs(la) <= 90.0 and abs(lo) <= 180.0 and not (abs(la) < 0.0001 and abs(lo) < 0.0001):
            lat = round_net(la, 6)
            lon = round_net(lo, 6)

    # Nadmořská výška
    m_alt = re.search(r'GPSAltitude(?!Ref)\s*(?:>|=["\'])\s*([^<"\']+)', content, re.IGNORECASE)
    if m_alt:
        alt_str = m_alt.group(1).strip()
        ref_str = "0"
        m_ref = re.search(r'GPSAltitudeRef\s*(?:>|=["\'])\s*([^<"\']+)', content, re.IGNORECASE)
        if m_ref: ref_str = m_ref.group(1).strip()
        try:
            if "/" in alt_str:
                num, den = alt_str.split("/", 1)
                raw_alt = float(num) / float(den)
            else:
                raw_alt = float(alt_str)
            if ref_str == "1": raw_alt = -abs(raw_alt)
            alt = PhotoRecordItem.valid_altitude(raw_alt)
        except Exception:
            pass

    if alt is None:
        # DJI AbsoluteAltitude
        m_abs = re.search(r'AbsoluteAltitude(?:>|=["\'])\s*"?([+-]?\d+(?:\.\d+)?)', content, re.IGNORECASE)
        if m_abs:
            try:
                alt = PhotoRecordItem.valid_altitude(float(m_abs.group(1)))
            except Exception:
                pass

    return date_str, lat, lon, alt

def parse_xmp_file(xmp_path):
    try:
        with open(xmp_path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
        d, la, lo, al = parse_xmp_text(content)
        if la is not None and lo is not None:
            return {
                "has_gps": True,
                "latitude": la,
                "longitude": lo,
                "altitude": al,
                "date_taken_str": d,
                "date_quality": 2 if d else 0
            }
    except Exception:
        pass
    return None

def parse_srt_file(srt_path):
    """
    Načte DJI .srt titulky k videu.
    """
    try:
        with open(srt_path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()

        re_lat = re.compile(r'(?<![A-Za-z_])(?:latitude|lat)\s*[:=]\s*([+-]?\d+(?:\.\d+)?)', re.IGNORECASE)
        re_lon = re.compile(r'(?<![A-Za-z_])(?:longt?itude|lon|long|lng)\s*[:=]\s*([+-]?\d+(?:\.\d+)?)', re.IGNORECASE)
        re_gps = re.compile(r'GPS\s*[(:]\s*([+-]?\d+(?:\.\d+)?)\s*,\s*([+-]?\d+(?:\.\d+)?)')
        re_alt = re.compile(r'(?<![A-Za-z_])(?:abs_alt|absoluteAltitude)\s*[:=]\s*([+-]?\d+(?:\.\d+)?)', re.IGNORECASE)

        blocks = re.split(r'\r?\n[ \t]*\r?\n', content)
        for bi, blk in enumerate(blocks):
            b_lat, b_lon = 0.0, 0.0
            b_ok = False
            m_lat = re_lat.search(blk)
            m_lon = re_lon.search(blk)
            if m_lat and m_lon:
                b_lat = float(m_lat.group(1))
                b_lon = float(m_lon.group(1))
                b_ok = True
            else:
                m_g = re_gps.search(blk)
                if m_g:
                    v1 = float(m_g.group(1))
                    v2 = float(m_g.group(2))
                    b_lon, b_lat = v1, v2
                    if abs(b_lat) > 90.0 and abs(b_lon) <= 90.0:
                        b_lat, b_lon = v1, v2
                    b_ok = True

            if not b_ok: continue
            if abs(b_lat) > 90.0 or abs(b_lon) > 180.0 or (abs(b_lat) < 0.0001 and abs(b_lon) < 0.0001):
                continue

            # Nadmořská výška (abs_alt)
            alt = None
            for ai in range(bi, len(blocks)):
                m_a = re_alt.search(blocks[ai])
                if m_a:
                    alt = PhotoRecordItem.valid_altitude(float(m_a.group(1)))
                    break

            # Datum z bloku
            m_time = re.search(r'(\d{4})[-_](\d{2})[-_](\d{2})\s+(\d{2}):(\d{2}):(\d{2})', blk)
            date_str = None
            if m_time:
                date_str = "".join(m_time.groups()[:3]) + "_" + "".join(m_time.groups()[3:])

            return {
                "has_gps": True,
                "latitude": round_net(b_lat, 6),
                "longitude": round_net(b_lon, 6),
                "altitude": alt,
                "date_taken_str": date_str,
                "date_quality": 2 if date_str else 0
            }
    except Exception:
        pass
    return None


# ==============================================================================
# JEDNOTLIVÉ ZPRACOVÁNÍ JEDNOHO SOUBORU (PRO MULTIPROCESSING)
# ==============================================================================
def process_single_media_file(args):
    """
    Zpracuje jeden mediální soubor (určeno pro paralelizaci).
    """
    filepath, root_dir = args
    fname = os.path.basename(filepath)
    ext = os.path.splitext(fname)[1].lower()
    rel_path = os.path.relpath(filepath, root_dir).replace("\\", "/")
    fsize = os.path.getsize(filepath)

    is_video = ext in VIDEO_EXTS
    if is_video:
        if ext in VIDEO_GPS_EXTS:
            date_str, lat, lon, alt, has_gps, dq = read_video_metadata(filepath)
        else:
            fn_date = parse_filename_datetime(fname)
            date_str = fn_date if fn_date else get_file_mtime_str(filepath)
            lat, lon, alt, has_gps, dq = 0.0, 0.0, None, False, 0
    else:
        date_str, lat, lon, alt, has_gps, dq = read_photo_metadata(filepath)

    return {
        "file_name": fname,
        "full_path": filepath,
        "relative_path": rel_path,
        "file_size": fsize,
        "is_video": is_video,
        "date_taken_str": date_str,
        "latitude": lat,
        "longitude": lon,
        "altitude": alt,
        "has_gps": has_gps,
        "date_quality": dq
    }


# ==============================================================================
# SKENOVÁNÍ ARCHIVU A DEDUPLIKACE (Volba [1] a [2])
# ==============================================================================
def scan_archive(target_dir):
    start_time = time.time()
    clean_target = os.path.abspath(target_dir)

    # 1. Shromáždění souborů
    media_files = []
    json_files = []
    xmp_files = []
    srt_files = []
    total_bytes = 0

    for root, dirs, files in os.walk(clean_target):
        # Vyfiltrovat systémové složky
        dirs[:] = [d for d in dirs if not is_junk_dir_name(d.lower())]

        for f in files:
            fl = f.lower()
            if is_own_output_file(fl) or is_junk_file_name(fl):
                continue
            full_path = os.path.join(root, f)
            ext = os.path.splitext(fl)[1]

            if ext in MEDIA_EXTS:
                media_files.append((full_path, clean_target))
                try: total_bytes += os.path.getsize(full_path)
                except Exception: pass
            elif ext == ".json":
                json_files.append(full_path)
            elif ext == ".xmp":
                xmp_files.append(full_path)
            elif ext == ".srt":
                srt_files.append(full_path)

    # 2. Paralelní zpracování médií (ThreadPool je bezpečný a rychlý napříč OS)
    from concurrent.futures import ThreadPoolExecutor
    workers = min(32, (os.cpu_count() or 4) * 2)
    with ThreadPoolExecutor(max_workers=workers) as executor:
        records_data = list(executor.map(process_single_media_file, media_files))

    # Převod na slovník dle relativní cesty
    media_by_rel = {}
    media_by_base = {}  # dir + basename -> record
    for r in records_data:
        media_by_rel[r["relative_path"]] = r
        dir_name = os.path.dirname(r["full_path"])
        base_no_ext = os.path.splitext(r["file_name"])[0].lower()
        key = (dir_name, base_no_ext)
        if key not in media_by_base:
            media_by_base[key] = []
        media_by_base[key].append(r)

    # 3. Párování a aplikace sidecar souborů
    # XMP
    RAW_FIRST_EXTS = (
        ".dng", ".cr2", ".cr3", ".nef", ".arw", ".raf", ".orf", ".rw2", ".pef", ".srw",
        ".jpg", ".jpeg", ".heic", ".heif", ".avif", ".tif", ".tiff", ".png", ".webp", ".bmp", ".gif",
        ".mp4", ".mov", ".m4v", ".avi", ".mkv", ".wmv", ".3gp", ".mts", ".m2ts", ".mpg", ".mpeg"
    )
    for xf in xmp_files:
        xdata = parse_xmp_file(xf)
        if not xdata: continue
        xdir = os.path.dirname(xf)
        xbase = os.path.splitext(os.path.basename(xf))[0].lower()
        key = (xdir, xbase)
        if key in media_by_base:
            cands = media_by_base[key]
            def ext_rank(item):
                e = os.path.splitext(item["file_name"])[1].lower()
                try: return RAW_FIRST_EXTS.index(e)
                except ValueError: return 999
            target_r = sorted(cands, key=ext_rank)[0]
            if not target_r["has_gps"] and xdata["has_gps"]:
                target_r["has_gps"] = True
                target_r["latitude"] = xdata["latitude"]
                target_r["longitude"] = xdata["longitude"]
            if target_r["altitude"] is None and xdata["altitude"] is not None:
                target_r["altitude"] = xdata["altitude"]
            if xdata["date_taken_str"] and xdata["date_quality"] > target_r["date_quality"]:
                target_r["date_taken_str"] = xdata["date_taken_str"]
                target_r["date_quality"] = xdata["date_quality"]

    # SRT (DJI drony)
    for sf in srt_files:
        sdata = parse_srt_file(sf)
        if not sdata: continue
        sdir = os.path.dirname(sf)
        sbase = os.path.splitext(os.path.basename(sf))[0].lower()
        key = (sdir, sbase)
        if key in media_by_base:
            for r in media_by_base[key]:
                if r["is_video"]:
                    if not r["has_gps"] and sdata["has_gps"]:
                        r["has_gps"] = True
                        r["latitude"] = sdata["latitude"]
                        r["longitude"] = sdata["longitude"]
                    if r["altitude"] is None and sdata["altitude"] is not None:
                        r["altitude"] = sdata["altitude"]
                    if sdata["date_taken_str"] and sdata["date_quality"] > r["date_quality"]:
                        r["date_taken_str"] = sdata["date_taken_str"]
                        r["date_quality"] = sdata["date_quality"]

    # Google JSON
    for jf in json_files:
        jdata = parse_google_json(jf)
        if not jdata: continue
        jdir = os.path.dirname(jf)
        # Možné protějšky fotek
        jname = os.path.basename(jf)
        cand_names = []
        if jname.endswith(".json"):
            cand_names.append(jname[:-5])  # photo.jpg.json -> photo.jpg
        if jdata["title"]:
            cand_names.append(jdata["title"])

        matched = []
        for cn in cand_names:
            cpath = os.path.relpath(os.path.join(jdir, cn), clean_target).replace("\\", "/")
            if cpath in media_by_rel:
                matched.append(media_by_rel[cpath])

        # Také zahrnout Live Photo videa a upravené kopie v téže složce
        if cand_names:
            base_cand = os.path.splitext(cand_names[0])[0].lower()
            clean_base = re.sub(r'-(?:edited|upraveno|upravené|bearbeitet|modifié|editado|modificato|bewerkt|edytowane|redigerad|muokattu)$', '', base_cand, flags=re.IGNORECASE)
            for k_base in (base_cand, clean_base):
                key = (jdir, k_base)
                if key in media_by_base:
                    for sibling in media_by_base[key]:
                        if sibling not in matched:
                            matched.append(sibling)

        for r in matched:
            if not r["has_gps"] and jdata["has_gps"]:
                r["has_gps"] = True
                r["latitude"] = jdata["latitude"]
                r["longitude"] = jdata["longitude"]
            if r["altitude"] is None and jdata["altitude"] is not None:
                r["altitude"] = jdata["altitude"]
            if jdata["date_taken_str"] != "00000000_000000" and jdata["date_quality"] > r["date_quality"]:
                r["date_taken_str"] = jdata["date_taken_str"]
                r["date_quality"] = jdata["date_quality"]

    # 4. Rozdělení na GPS a bez-GPS záznamy
    gps_items = []
    no_gps_items = []

    for r in records_data:
        item = PhotoRecordItem(
            file_name=r["file_name"],
            date_taken_str=r["date_taken_str"],
            latitude=r["latitude"],
            longitude=r["longitude"],
            altitude=r["altitude"],
            relative_path=r["relative_path"],
            file_size_bytes=r["file_size"],
            has_gps=r["has_gps"],
            date_quality=r["date_quality"]
        )
        if item.has_gps:
            gps_items.append(item)
        else:
            item.status = "S"
            item.altitude = None
            no_gps_items.append(item)

    # 5. Řazení před deduplikací (chronologicky, název, relativní cesta - odpovídá StringComparison.OrdinalIgnoreCase v .NET)
    def sort_key(it):
        return (it.date_taken_str, it.file_name.upper(), it.relative_path.upper())

    gps_items.sort(key=sort_key)
    gps_before_dedup = len(gps_items)

    # 6. Deduplikace záznamů s GNSS
    exact_seen = set()
    by_file_pos = {}
    dup_list = []

    for r in gps_items:
        exact_key = f"{r.date_taken_str}|{r.file_name.lower()}|{r.latitude:.6f}|{r.longitude:.6f}"
        if exact_key in exact_seen:
            r.status = "D"
            dup_list.append(r)
            continue
        exact_seen.add(exact_key)

        base_no_ext = os.path.splitext(r.file_name)[0].lower()
        pos_key = f"{base_no_ext}|{r.latitude:.4f}|{r.longitude:.4f}"

        if pos_key in by_file_pos:
            existing = by_file_pos[pos_key]
            exi_zero = existing.date_taken_str.startswith("00000000")
            cur_zero = r.date_taken_str.startswith("00000000")
            if exi_zero and not cur_zero:
                existing.status = "D"
                dup_list.append(existing)
                by_file_pos[pos_key] = r
            else:
                r.status = "D"
                dup_list.append(r)
            continue

        by_file_pos[pos_key] = r

    # Doplnění nadmořské výšky z duplicit do zachovaného záznamu G
    for r in dup_list:
        if r.altitude is not None:
            base_no_ext = os.path.splitext(r.file_name)[0].lower()
            pos_key = f"{base_no_ext}|{r.latitude:.4f}|{r.longitude:.4f}"
            if pos_key in by_file_pos:
                kept = by_file_pos[pos_key]
                if kept.altitude is None:
                    kept.altitude = r.altitude

    deduped_gps = list(by_file_pos.values())
    for g in deduped_gps:
        g.status = "G"

    deduped_gps.sort(key=sort_key)
    dup_list.sort(key=sort_key)
    no_gps_items.sort(key=sort_key)

    all_records = deduped_gps + dup_list + no_gps_items
    all_records.sort(key=sort_key)

    elapsed = time.time() - start_time
    return {
        "total_files": len(media_files),
        "total_bytes": total_bytes,
        "gps_before_dedup": gps_before_dedup,
        "gps_records": deduped_gps,
        "dup_records": dup_list,
        "no_gps_records": no_gps_items,
        "all_records": all_records,
        "elapsed_sec": elapsed
    }


# ==============================================================================
# STATISTIKA ARCHIVU (Volba [3])
# ==============================================================================
def generate_folder_statistics(root_dir):
    clean_root = os.path.abspath(root_dir).rstrip("/\\")
    folder_stats = []

    for root, dirs, files in os.walk(clean_root):
        dirs[:] = [d for d in dirs if not is_junk_dir_name(d.lower())]
        dirs.sort(key=lambda s: s.upper())

        valid_files = []
        dir_bytes = 0

        for f in files:
            fl = f.lower()
            if is_own_output_file(fl) or is_junk_file_name(fl): continue
            ext = os.path.splitext(fl)[1]
            if ext not in MEDIA_EXTS: continue

            fp = os.path.join(root, f)
            sz = os.path.getsize(fp)
            dir_bytes += sz

            d_str = get_file_date_string(fp)
            valid_files.append((d_str, f, sz))

        if not valid_files:
            continue

        valid_files.sort(key=lambda x: (x[0], x[1].upper()))
        oldest_str = valid_files[0][0]
        newest_str = valid_files[-1][0]

        rel = os.path.relpath(root, clean_root).replace("\\", "/")
        if rel == ".":
            rel = os.path.basename(clean_root)
        key = rel.replace("/", "_").replace("\\", "_")

        folder_stats.append({
            "key": key,
            "rel": rel,
            "count": len(valid_files),
            "bytes": dir_bytes,
            "oldest": oldest_str,
            "newest": newest_str
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
            lat_str = f"{item.latitude:.6f}"
            lon_str = f"{item.longitude:.6f}"
        alt_str = f"{item.altitude:.1f}" if item.altitude is not None else ""
        row = f"{item.date_taken_str};{tab}{item.file_name};{tab}{lat_str};{tab}{lon_str};{tab}{item.file_size_bytes};{tab}{item.relative_path};{tab}{st};{tab}{alt_str}"
        lines.append(row)

    lines.append("`;\n")

    content = "\n".join(lines)
    # Zápis v UTF-8 s BOM (přesně shodné s BAT)
    with open(output_filepath, "w", encoding="utf-8-sig") as f:
        f.write(content)

def save_stats_csv(output_filepath, folder_stats, is_en=False):
    today_dt = datetime.datetime.now().strftime("%d.%m.%Y %H:%M:%S")

    # Tabulka 1: Detailní složky
    t1_header = "SLOZKA; NEJSTARSI_SOUBOR; NEJNOVEJSI_SOUBOR; POCET_SOUBORU; VELIKOST_BAJTY; VELIKOST_GB" if not is_en else "FOLDER; OLDEST_FILE; NEWEST_FILE; FILE_COUNT; SIZE_BYTES; SIZE_GB"
    lines = [
        f"// Vygenerovano: {today_dt}",
        t1_header
    ]

    total_files = 0
    total_bytes = 0
    all_oldest = []
    all_newest = []

    for fs in folder_stats:
        gb_val = fs["bytes"] / (1024.0 ** 3)
        gb_str = f"{gb_val:.3f}".replace(".", ",")
        lines.append(f"{fs['key']}; {fs['oldest']}; {fs['newest']}; {fs['count']}; {fs['bytes']}; {gb_str}")
        total_files += fs["count"]
        total_bytes += fs["bytes"]
        if fs["oldest"] != "-": all_oldest.append(fs["oldest"])
        if fs["newest"] != "-": all_newest.append(fs["newest"])

    global_oldest = min(all_oldest) if all_oldest else "-"
    global_newest = max(all_newest) if all_newest else "-"
    tot_gb_str = f"{(total_bytes / (1024.0 ** 3)):.3f}".replace(".", ",")
    tot_label = "CELKEM" if not is_en else "TOTAL"
    lines.append(f"{tot_label}; {global_oldest}; {global_newest}; {total_files}; {total_bytes}; {tot_gb_str}")

    lines.append("")
    lines.append("")

    # Tabulka 2: Agregace za hlavní složky 1. úrovně
    lines.append(t1_header)
    main_folders = {}
    for fs in folder_stats:
        parts = fs["rel"].split("/")
        top = parts[0] if parts else fs["rel"]
        if top not in main_folders:
            main_folders[top] = {"count": 0, "bytes": 0, "oldest": [], "newest": []}
        main_folders[top]["count"] += fs["count"]
        main_folders[top]["bytes"] += fs["bytes"]
        if fs["oldest"] != "-": main_folders[top]["oldest"].append(fs["oldest"])
        if fs["newest"] != "-": main_folders[top]["newest"].append(fs["newest"])

    for top in sorted(main_folders.keys(), key=lambda s: s.lower()):
        mf = main_folders[top]
        o_str = min(mf["oldest"]) if mf["oldest"] else "-"
        n_str = max(mf["newest"]) if mf["newest"] else "-"
        gb_str = f"{(mf['bytes'] / (1024.0 ** 3)):.3f}".replace(".", ",")
        lines.append(f"{top}; {o_str}; {n_str}; {mf['count']}; {mf['bytes']}; {gb_str}")

    lines.append(f"{tot_label}; {global_oldest}; {global_newest}; {total_files}; {total_bytes}; {tot_gb_str}")
    lines.append("")

    content = "\n".join(lines)
    with open(output_filepath, "w", encoding="utf-8-sig") as f:
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
            save_stats_csv(out_csv, stats_list, is_en=is_en)
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
            rel_sub = os.path.relpath(chosen, root_dir).replace("\\", "/").strip("/.")
            if rel_sub:
                picked_suffix = "_" + rel_sub.replace("/", "_")

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
