#!/usr/bin/env python3
import argparse
import base64
import os
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec


def parse_args():
    parser = argparse.ArgumentParser(description="Generate the Xiuhui activation signing key")
    parser.add_argument("--private-out", required=True, type=Path)
    parser.add_argument("--public-out", required=True, type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.private_out.exists():
        raise SystemExit(f"Refusing to overwrite existing private key: {args.private_out}")

    key = ec.generate_private_key(ec.SECP256R1())
    private_pem = key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    )
    public_raw = key.public_key().public_bytes(
        serialization.Encoding.X962,
        serialization.PublicFormat.UncompressedPoint,
    )

    args.private_out.parent.mkdir(parents=True, exist_ok=True)
    args.public_out.parent.mkdir(parents=True, exist_ok=True)
    args.private_out.write_bytes(private_pem)
    os.chmod(args.private_out, 0o600)
    args.public_out.write_text(base64.b64encode(public_raw).decode("ascii") + "\n", encoding="ascii")
    print(f"Private key: {args.private_out}")
    print(f"Public key:  {args.public_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
