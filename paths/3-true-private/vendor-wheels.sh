#!/usr/bin/env bash
#
# vendor-wheels.sh — download the Flask + pymysql wheel set for the true-private
# (zero-internet) deploy.
#
# WHY: with no NAT/IGW the target EC2 has no route to PyPI. We pre-download the
# wheels here (on your internet-connected laptop) and Terraform uploads them to
# a private S3 bucket; the instance installs them via the S3 Gateway endpoint
# with `pip install --no-index`.
#
# The target is Amazon Linux 2023: system Python 3.9, Linux x86_64 (manylinux).
# We pin --platform / --python-version / --only-binary so the wheels match the
# INSTANCE, not this laptop (which may be macOS/arm64).
#
# USAGE:
#   ./vendor-wheels.sh            # downloads into ./wheels
# Then:
#   terraform apply
#
# Re-running is safe (idempotent) — it just re-populates ./wheels.

set -euo pipefail

cd "$(dirname "$0")"

WHEELS_DIR="./wheels"
PY_VERSION="3.9"
PLATFORM="manylinux2014_x86_64"

# Pinned to match the module's user_data.sh.tftpl.
FLASK_VERSION="3.0.3"
PYMYSQL_VERSION="1.1.1"

echo "==> Preparing ${WHEELS_DIR}"
rm -rf "${WHEELS_DIR}"
mkdir -p "${WHEELS_DIR}"

# Resolve a python with pip on this machine.
PYBIN="${PYTHON:-python3}"
if ! "${PYBIN}" -m pip --version >/dev/null 2>&1; then
  echo "ERROR: '${PYBIN} -m pip' not available. Install pip or set PYTHON=/path/to/python3." >&2
  exit 1
fi

echo "==> Downloading wheels for Python ${PY_VERSION} / ${PLATFORM}"
# --only-binary=:all: forces real wheels (no sdists that would need a compiler
#   on the target). --platform + --python-version make pip fetch the TARGET's
#   wheels, not this host's.
#
# NOTE: environment-marker deps are evaluated against the HOST interpreter, not
# --python-version. The AL2023 target is Python 3.9, and Flask declares
#   importlib-metadata>=3.6.0 ; python_version < "3.10"
# which a 3.10+ laptop would skip. We therefore request importlib-metadata (and
# its own dep, zipp) EXPLICITLY so the py3.9 target has them for the offline
# `pip install --no-index`.
"${PYBIN}" -m pip download \
  --dest "${WHEELS_DIR}" \
  --only-binary=:all: \
  --platform "${PLATFORM}" \
  --platform any \
  --python-version "${PY_VERSION}" \
  "flask==${FLASK_VERSION}" \
  "pymysql==${PYMYSQL_VERSION}" \
  "importlib-metadata>=3.6.0" \
  "zipp"

echo
echo "==> Vendored $(ls -1 "${WHEELS_DIR}" | wc -l | tr -d ' ') files into ${WHEELS_DIR}:"
ls -1 "${WHEELS_DIR}"
echo
echo "Done. Now run: terraform apply"
