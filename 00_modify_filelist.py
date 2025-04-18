#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import sys
import io

def main():
    if len(sys.argv) != 2:
        print("Usage: modify_filelist.py <path_to_filelist.xml>")
        sys.exit(1)
    path = sys.argv[1]

    # 1) Read the XML (handle a UTF-8 BOM if present)
    with io.open(path, 'r', encoding='utf-8-sig') as f:
        lines = f.readlines()

    # 2) Remove any lines containing "ArchiveAndReference"
    filtered = [l for l in lines if "ArchiveAndReference" not in l]

    # 3) Join back and replace the name‑attribute in one go
    content = "".join(filtered)
    content = content.replace(
        'name="[EA-HI]木卫二萌化计划-DEV"',
        'name="[EA-HI]木卫二萌化计划" steamworkshopid="2809175631"'
    )

    # 4) Write back as UTF‑8 (with BOM)
    with io.open(path, 'w', encoding='utf-8-sig') as f:
        f.write(content)

if __name__ == "__main__":
    main()
