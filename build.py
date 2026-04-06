"""
build.py — KungRC EA Build Script
รัน: python build.py [patch|minor|major]

  patch  (default) : 1.0.0 → 1.0.1
  minor            : 1.0.1 → 1.1.0
  major            : 1.1.0 → 2.0.0
"""
import os
import re
import sys
import subprocess
sys.stdout.reconfigure(encoding="utf-8") if hasattr(sys.stdout, "reconfigure") else None

BASE = os.path.dirname(os.path.abspath(__file__))

VER_FILE      = os.path.join(BASE, "version.txt")
ISS_FILE      = os.path.join(BASE, "installer.iss")
SPEC_FILE     = os.path.join(BASE, "kungrc.spec")
CHANGELOG     = os.path.join(BASE, "CHANGELOG.txt")
PYINSTALLER   = os.path.join(BASE, ".venv", "Scripts", "pyinstaller.exe")
INNO          = r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe"


def read_version() -> tuple[int,int,int]:
    with open(VER_FILE) as f:
        parts = f.read().strip().split(".")
    return int(parts[0]), int(parts[1]), int(parts[2])


def bump_version(bump: str) -> str:
    ma, mi, pa = read_version()
    if   bump == "major": ma += 1; mi = 0; pa = 0
    elif bump == "minor": mi += 1; pa = 0
    else:                 pa += 1          # patch (default)
    ver = f"{ma}.{mi}.{pa}"
    with open(VER_FILE, "w") as f:
        f.write(ver)
    return ver


def update_all(ver: str, bump: str):
    # ชื่อไฟล์ตาม bump type
    # installer.iss — อัปเดตแค่ AppVersion, OutputBaseFilename คง "KungRC_EA_install" ตลอด
    with open(ISS_FILE, encoding="utf-8") as f:
        txt = f.read()
    txt = re.sub(r'(#define AppVersion\s+")[^"]*(")', rf'\g<1>{ver}\2', txt)
    with open(ISS_FILE, "w", encoding="utf-8") as f:
        f.write(txt)
    print(f"[build] installer.iss    → v{ver}  (KungRC_EA_install.exe)")
    # CHANGELOG.txt — อัปเดต header ถ้ายังไม่มี version นี้
    with open(CHANGELOG, encoding="utf-8") as f:
        cl = f.read()
    if f"Version {ver}" not in cl:
        insert = f"Version {ver}\n" + "-"*len(f"Version {ver}") + "\n- (รายการเปลี่ยนแปลง)\n\n"
        cl = cl.replace("Version ", insert + "Version ", 1)
        with open(CHANGELOG, "w", encoding="utf-8") as f:
            f.write(cl)
        print(f"[build] CHANGELOG.txt    → เพิ่ม Version {ver} (กรุณาแก้รายละเอียด)")


def show_changelog():
    print("\n" + "="*55)
    print("  CHANGELOG.txt — รายการเปลี่ยนแปลงที่จะแสดงใน installer")
    print("="*55)
    with open(CHANGELOG, encoding="utf-8") as f:
        print(f.read())
    print("="*55)
    answer = input("แก้ไข CHANGELOG.txt ก่อนดำเนินการต่อ? [y/N]: ").strip().lower()
    if answer == "y":
        os.startfile(CHANGELOG)
        input("กด Enter เมื่อแก้ไขเสร็จแล้ว...")


def kill_exe():
    for name in ["KungRC_EA.exe", "KungRC_Launcher.exe"]:
        subprocess.call(["taskkill", "/f", "/im", name],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def run(cmd: list, **kw):
    print(f"[build] {' '.join(cmd)}")
    result = subprocess.run(cmd, **kw)
    if result.returncode != 0:
        print(f"[build] ERROR: exit code {result.returncode}")
        sys.exit(result.returncode)


def main():
    bump = sys.argv[1] if len(sys.argv) > 1 else "patch"
    if bump not in ("patch", "minor", "major"):
        print(f"usage: python build.py [patch|minor|major]")
        sys.exit(1)

    # ── 1. Bump version ────────────────────────────────────────
    ver = bump_version(bump)
    print(f"\n[build] Version: {ver}  (bump={bump})")

    # ── 2. Sync version everywhere ─────────────────────────────
    update_all(ver, bump)

    # ── 3. Changelog ───────────────────────────────────────────
    show_changelog()

    # ── 3. Kill running EXE ────────────────────────────────────
    print("[build] Killing running EXEs...")
    kill_exe()

    # ── 4. PyInstaller ─────────────────────────────────────────
    print("\n[build] Building EXE...")
    run([PYINSTALLER, "--noconfirm", SPEC_FILE], cwd=BASE)

    # ── 5. Inno Setup ──────────────────────────────────────────
    print("\n[build] Packing installer...")
    run([INNO, ISS_FILE], cwd=BASE)

    label = {"patch": "patch", "minor": "update", "major": "release"}.get(bump, "patch")
    out = os.path.join(BASE, "dist", "KungRC_EA_install.exe")
    print(f"\n{'='*55}")
    print(f"  BUILD COMPLETE")
    print(f"  Version  : {ver}")
    print(f"  Installer: {out}")
    print(f"{'='*55}\n")


if __name__ == "__main__":
    main()
