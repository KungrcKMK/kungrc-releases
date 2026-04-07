# ============================================================
#  KungRC EA — PyInstaller Spec File
#  สร้าง 2 EXE ใน folder เดียว (--onedir):
#    KungRC_Launcher.exe  ← user double-click ตัวนี้
#    KungRC_EA.exe        ← launcher เรียกอัตโนมัติ
# ============================================================
import os, re
from PyInstaller.utils.hooks import collect_data_files

block_cipher = None

# ── Paths ──────────────────────────────────────────────────────
SRC  = SPECPATH   # SPECPATH = โฟลเดอร์ที่ spec file อยู่ (PyInstaller built-in)
VENV = os.path.join(SRC, '.venv', 'Lib', 'site-packages')
CTK  = os.path.join(VENV, 'customtkinter')

# ── อ่าน version แล้ว inject เข้า file_version_info.txt ────────
with open(os.path.join(SRC, 'version.txt'), encoding='utf-8') as _f:
    _ver_str = _f.read().strip()          # เช่น "1.0.51"
_parts = [int(x) for x in _ver_str.split('.')]
while len(_parts) < 4:
    _parts.append(0)
_ver_tuple = tuple(_parts)               # (1, 0, 51, 0)
_ver_file   = os.path.join(SRC, 'file_version_info.txt')
with open(_ver_file, encoding='utf-8') as _f:
    _vfi = _f.read()
_vfi = re.sub(r'filevers=\(.*?\)', f'filevers={_ver_tuple}', _vfi)
_vfi = re.sub(r'prodvers=\(.*?\)', f'prodvers={_ver_tuple}', _vfi)
_vfi = re.sub(r"(FileVersion\',\s*u\')[\d.]+", rf"\g<1>{_ver_str}.0", _vfi)
_vfi = re.sub(r"(ProductVersion\',\s*u\')[\d.]+", rf"\g<1>{_ver_str}.0", _vfi)
with open(_ver_file, 'w', encoding='utf-8') as _f:
    _f.write(_vfi)

# ── Bundled assets (read-only → _MEIPASS) ─────────────────────
#    customtkinter ต้องการ assets/ ไม่งั้น theme/font หาย
datas = [
    (os.path.join(CTK, 'assets'), 'customtkinter/assets'),
    (os.path.join(SRC, 'version.txt'), '.'),
    (os.path.join(SRC, 'build_date.txt'), '.'),
    (os.path.join(SRC, 'latest.json'), '.'),
    (os.path.join(SRC, 'mql_template_mt5.mq5'), '.'),
]

# ── Hidden imports ─────────────────────────────────────────────
#    PyInstaller ไม่ตาม dynamic imports อัตโนมัติ
hiddenimports = [
    'customtkinter',
    'PIL._tkinter_finder',
    'PIL.Image',
    'pandas',
    'pandas._libs.interval',
    'pandas._libs.hashtable',
    'pandas._libs.lib',
    'numpy',
    'numpy.core._multiarray_umath',
    'MetaTrader5',
    'requests',
    'urllib.request',
    'urllib.error',
    'csv',
    'json',
    'hashlib',
    'base64',
    'threading',
    'queue',
    'tkinter',
    'tkinter.font',
    'tkinter.ttk',
]

# ── Packages ที่ไม่ต้องการ (ลดขนาดไฟล์) ──────────────────────
excludes = [
    'matplotlib', 'scipy', 'sklearn', 'IPython', 'jupyter',
    'notebook', 'sphinx', 'pytest', 'setuptools', 'distutils',
    'tkinter.test', 'unittest', 'doctest', 'pydoc',
    'xmlrpc', 'ftplib', 'imaplib', 'smtplib', 'poplib',
    'curses', 'turtle', 'turtledemo',
]

# ── Common kwargs สำหรับทั้ง 2 Analysis ───────────────────────
_common = dict(
    pathex           = [SRC],
    binaries         = [],
    datas            = datas,
    hiddenimports    = hiddenimports,
    hookspath        = [],
    hooksconfig      = {},
    runtime_hooks    = [],
    excludes         = excludes,
    noarchive        = False,
    cipher           = block_cipher,
)

# ════════════════════════════════════════════════════════════════
#  1) KungRC_Launcher.exe
# ════════════════════════════════════════════════════════════════
a_launcher = Analysis(
    ['launcher.py'],
    **_common,
)

pyz_launcher = PYZ(
    a_launcher.pure,
    a_launcher.zipped_data,
    cipher=block_cipher,
)

exe_launcher = EXE(
    pyz_launcher,
    a_launcher.scripts,
    [],
    exclude_binaries = True,
    name             = 'KungRC_Launcher',
    debug            = False,
    strip            = False,
    upx              = False,       # อย่าใช้ UPX — อาจ trigger antivirus
    console          = False,       # ไม่แสดง console window
    icon             = os.path.join(SRC, 'kungrc.ico'),
    version          = _ver_file,
)

# ════════════════════════════════════════════════════════════════
#  2) KungRC_EA.exe  (EA instance — เรียกโดย launcher)
# ════════════════════════════════════════════════════════════════
a_ea = Analysis(
    ['main.py'],
    **_common,
)

pyz_ea = PYZ(
    a_ea.pure,
    a_ea.zipped_data,
    cipher=block_cipher,
)

exe_ea = EXE(
    pyz_ea,
    a_ea.scripts,
    [],
    exclude_binaries = True,
    name             = 'KungRC_EA',
    debug            = False,
    strip            = False,
    upx              = False,
    console          = False,
    icon             = os.path.join(SRC, 'kungrc.ico'),
    version          = _ver_file,
)

# ════════════════════════════════════════════════════════════════
#  COLLECT — รวม 2 EXE ใน dist/KungRC_EA/
# ════════════════════════════════════════════════════════════════
coll = COLLECT(
    exe_launcher,
    a_launcher.binaries,
    a_launcher.zipfiles,
    a_launcher.datas,

    exe_ea,
    a_ea.binaries,
    a_ea.zipfiles,
    a_ea.datas,

    strip      = False,
    upx        = False,
    upx_exclude= [],
    name       = 'KungRC_EA',    # → dist/KungRC_EA/
)
