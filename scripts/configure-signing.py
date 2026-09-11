#!/usr/bin/env python3
"""Select an existing signing identity; never create/export private keys."""
from pathlib import Path
import os
import re
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
requested = os.environ.get("SIGNING_IDENTITY", "Apple Development")
identities = subprocess.check_output(["security", "find-identity", "-v", "-p", "codesigning"], text=True)
candidates = [(fingerprint, name) for fingerprint, name in
              re.findall(r'^\s*\d+\) ([A-Fa-f0-9]{40}) "([^"]+)"', identities, re.MULTILINE)
              if fingerprint.lower() == requested.lower() or name == requested or name.startswith(requested + ":")]
if len(candidates) != 1:
    sys.exit("Select one valid signing certificate with SIGNING_IDENTITY (name or fingerprint). "
             "If none exists, create an Apple Development certificate in Xcode → Settings → Accounts. "
             "Ad-hoc signing is not used because it invalidates Screen Recording grants on rebuild.")
fingerprint, name = candidates[0]
certificates = subprocess.check_output(["security", "find-certificate", "-a", "-c", name, "-p"], text=True)
team = None
for certificate in re.findall(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", certificates, re.DOTALL):
    details = subprocess.check_output(["openssl", "x509", "-noout", "-fingerprint", "-sha1",
                                       "-subject", "-nameopt", "sep_multiline"], input=certificate, text=True)
    cert_hash = re.search(r"Fingerprint=([A-Fa-f0-9:]+)", details)
    if cert_hash and cert_hash[1].replace(":", "").lower() == fingerprint.lower():
        unit = re.search(r"^\s*OU\s*=\s*([A-Z0-9]{10})\s*$", details, re.MULTILINE)
        if unit:
            team = unit[1]
        break
if not team:
    sys.exit("Could not determine the selected certificate's Apple development team.")
settings = f"// Local signing selection; generated from an existing keychain identity.\nCODE_SIGN_IDENTITY = {fingerprint}\nDEVELOPMENT_TEAM = {team}\n"
destination = root / "Signing.local.xcconfig"
if not destination.exists() or destination.read_text() != settings:
    destination.write_text(settings)
print("Configured certificate signing in Signing.local.xcconfig.")
