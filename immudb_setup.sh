#!/bin/bash
set -e
# Build immudb binaries inside Alpine (proot-distro) and check versions

echo "[*] Updating Alpine packages..."
apk update && apk upgrade

echo "[*] Installing build dependencies..."
apk add --no-cache git make clang cmake go libc-dev bash

echo "[*] Verifying toolchain versions..."
git --version
make --version
clang --version
go version

mkdir -p "$HOME/bin"

# Clone immudb if not already present
if [ ! -d "$HOME/immudb" ]; then
  echo "[*] Cloning immudb source..."
  git clone --depth=1 --branch v1.10.0 https://github.com/codenotary/immudb.git "$HOME/immudb"
fi

cd "$HOME/immudb"

# Build binaries only if missing
if [ ! -f "$HOME/bin/immudb" ] || [ ! -f "$HOME/bin/immuclient" ] || [ ! -f "$HOME/bin/immuadmin" ]; then
  echo "[*] Building immudb binaries..."
  make immudb immuclient immuadmin
  cp immudb immuclient immuadmin "$HOME/bin/"
else
  echo "[*] Binaries already present, skipping rebuild."
fi

echo "[*] Checking immudb binary versions..."
"$HOME/bin/immudb" version || true
"$HOME/bin/immuclient" version || true
"$HOME/bin/immuadmin" version || true

echo "[*] Build and version check complete."
localhost:~# cat s.sh
#!/bin/bash
set -e
# Build immudb binaries inside Alpine (proot-distro) and check versions

echo "[*] Updating Alpine packages..."
apk update && apk upgrade

echo "[*] Installing build dependencies..."
apk add --no-cache git make clang cmake go libc-dev bash

echo "[*] Verifying toolchain versions..."
git --version
make --version
clang --version
go version

mkdir -p "$HOME/bin"

# Clone immudb if not already present
if [ ! -d "$HOME/immudb" ]; then
  echo "[*] Cloning immudb source..."
  git clone --depth=1 --branch v1.10.0 https://github.com/codenotary/immudb.git "$HOME/immudb"
fi

cd "$HOME/immudb"

# Build binaries only if missing
if [ ! -f "$HOME/bin/immudb" ] || [ ! -f "$HOME/bin/immuclient" ] || [ ! -f "$HOME/bin/immuadmin" ]; then
  echo "[*] Building immudb binaries..."
  make immudb immuclient immuadmin
  cp immudb immuclient immuadmin "$HOME/bin/"
else
  echo "[*] Binaries already present, skipping rebuild."
fi

echo "[*] Checking immudb binary versions..."
"$HOME/bin/immudb" version || true
"$HOME/bin/immuclient" version || true
"$HOME/bin/immuadmin" version || true

echo "[*] Build and version check complete."
