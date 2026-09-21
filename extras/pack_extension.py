#!/usr/bin/env python3
"""
VirusDownloader Extension Packager
Generates deterministic RSA key, injects public key into manifest.json,
and packages extras/extension into extras/extension.crx and extras/update.xml.
"""

import os
import sys
import json
import base64
import binascii
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
EXTRAS_DIR = ROOT_DIR / "extras"
EXT_DIR = EXTRAS_DIR / "extension"
PEM_PATH = EXTRAS_DIR / "extension.pem"
CRX_PATH = EXTRAS_DIR / "extension.crx"
UPDATE_XML_PATH = EXTRAS_DIR / "update.xml"
MANIFEST_PATH = EXT_DIR / "manifest.json"

try:
    from crx3 import creator, id_util, key_util
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "crx3"])
    from crx3 import creator, id_util, key_util


def ensure_key():
    env_pem = os.environ.get("EXTENSION_PEM_KEY")
    if env_pem and env_pem.strip():
        PEM_PATH.write_text(env_pem.strip() + "\n", encoding="utf-8")

    if not PEM_PATH.exists():
        if CRX_PATH.exists() and UPDATE_XML_PATH.exists():
            print(f"Notice: {PEM_PATH.name} not found; using existing pre-built {CRX_PATH.name}")
            return None, None
        print(f"Generating new private key at {PEM_PATH}...")
        creator.create_private_key_file(str(PEM_PATH))

    with open(PEM_PATH, "rb") as f:
        key_data = f.read()

    key = key_util.load_private_key_from_pem(key_data)
    pub = key_util.extract_public_key_from_private_key(key)
    pub_der = key_util.get_public_key_data(pub)
    ext_id_bytes = id_util.calc_crx_id_by_public_key(pub_der)
    ext_id = id_util.convert_hex_crx_id_to_alphabet(binascii.hexlify(ext_id_bytes).decode("ascii"))
    pub_b64 = base64.b64encode(pub_der).decode("ascii")

    return ext_id, pub_b64


def update_manifest(pub_b64):
    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    manifest["key"] = pub_b64
    version = manifest.get("version", "1.0.0")

    with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")

    return version


def create_update_xml(ext_id, version, out_path=UPDATE_XML_PATH):
    xml_content = f"""<?xml version='1.0' encoding='UTF-8'?>
<gupdate xmlns='http://www.google.com/update2/response' protocol='2.0'>
  <app appid='{ext_id}'>
    <updatecheck codebase='http://127.0.0.1:9849/extension.crx' version='{version}' />
  </app>
</gupdate>
"""
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(xml_content)
    print(f"Generated {out_path}")


def pack_crx(out_path=CRX_PATH):
    print(f"Packing extension from {EXT_DIR} to {out_path}...")
    creator.create_crx_file(str(EXT_DIR), str(PEM_PATH), str(out_path))
    print(f"Successfully created {out_path} ({os.path.getsize(out_path)} bytes)")


def main():
    ext_id, pub_b64 = ensure_key()
    if ext_id is not None and pub_b64 is not None:
        print(f"Extension ID: {ext_id}")
        version = update_manifest(pub_b64)
        print(f"Updated manifest.json with public key, version: {version}")
        create_update_xml(ext_id, version)
        pack_crx()
    else:
        print("Using existing extension.crx and update.xml")

    # If an output directory argument is provided (e.g. during build / staging), copy there too
    if len(sys.argv) > 1:
        target_dir = Path(sys.argv[1])
        target_dir.mkdir(parents=True, exist_ok=True)
        import shutil
        shutil.copy2(UPDATE_XML_PATH, target_dir / "update.xml")
        shutil.copy2(CRX_PATH, target_dir / "extension.crx")


if __name__ == "__main__":
    main()
