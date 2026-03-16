# Installation script for Ollama MultiModal LLM by OmegaIT
# Called from CodeProject.AI setup with first argument "install"
# Installs Ollama into the module folder (per https://docs.ollama.com/linux manual install)
# so it persists when the module lives on a volume (e.g. Docker /app/modules).

if [ "$1" != "install" ]; then
  echo "This script is only called from CodeProject.AI setup.sh"
  exit 0
fi

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
OLLAMA_INSTALL_DIR="${OLLAMA_INSTALL_DIR:-$MODULE_DIR/ollama}"
OLLAMA_MODELS_DIR="${OLLAMA_MODELS_DIR:-$MODULE_DIR/models}"

writeLine "Checking prerequisites for Ollama MultiModal LLM by OmegaIT..." "cyan"

# Detect arch for manual install (per https://docs.ollama.com/linux)
case "$(uname -m)" in
  x86_64|amd64) OLLAMA_ARCH="amd64" ;;
  aarch64|arm64) OLLAMA_ARCH="arm64" ;;
  *) OLLAMA_ARCH="amd64" ;;
esac

# Resolve path to ollama binary: prefer module install, then PATH
ollama_bin() {
  if [ -x "$OLLAMA_INSTALL_DIR/bin/ollama" ]; then
    echo "$OLLAMA_INSTALL_DIR/bin/ollama"
    return
  fi
  if [ -x "$OLLAMA_INSTALL_DIR/usr/bin/ollama" ]; then
    echo "$OLLAMA_INSTALL_DIR/usr/bin/ollama"
    return
  fi
  if command -v ollama &>/dev/null; then
    echo "ollama"
    return
  fi
  echo ""
}

# 1. Install Ollama into module folder if not already present (Linux manual install per docs.ollama.com/linux)
if [ "$(uname -s)" = "Linux" ] && { [ ! -x "$OLLAMA_INSTALL_DIR/bin/ollama" ] && [ ! -x "$OLLAMA_INSTALL_DIR/usr/bin/ollama" ]; }; then
  writeLine "  Ollama not found in module dir. Installing Ollama into module folder (manual install)..." "yellow"
  if ! command -v curl &>/dev/null; then
    writeLine "  [FAIL] curl is required. Install curl and re-run setup." "red"
    writeLine "  Continuing with Python dependencies; install Ollama manually from https://ollama.com" "yellow"
  else
    # .tar.zst requires zstd to decompress before tar; pipe breaks (curl 23) if tar gets compressed bytes
    if ! command -v zstd &>/dev/null; then
      writeLine "  Installing zstd for tarball extraction..." "cyan"
      if command -v apt-get &>/dev/null; then
        apt-get update -qq 2>/dev/null || true
        apt-get install -y -qq zstd 2>/dev/null || true
      fi
    fi
    if ! command -v zstd &>/dev/null; then
      writeLine "  [FAIL] zstd is required to extract Ollama tarball. Install zstd and re-run." "red"
      writeLine "  apt-get install -y zstd" "yellow"
    else
      mkdir -p "$OLLAMA_INSTALL_DIR"
      cd "$OLLAMA_INSTALL_DIR"
      # Manual install: download, decompress with zstd, extract (per https://docs.ollama.com/linux)
      TARBALL="ollama-linux-${OLLAMA_ARCH}.tar.zst"
      URL="https://ollama.com/download/${TARBALL}"
      writeLine "  Downloading $URL ..." "cyan"
      if curl -fsSL "$URL" | zstd -d | tar -x; then
        # AMD ROCm (optional, per https://docs.ollama.com/linux)
        if [ "${OLLAMA_USE_ROCM:-0}" = "1" ] && [ "$OLLAMA_ARCH" = "amd64" ]; then
          writeLine "  Downloading Ollama ROCm libraries for AMD GPU..." "cyan"
          curl -fsSL "https://ollama.com/download/ollama-linux-amd64-rocm.tar.zst" | zstd -d | tar -x
        fi
        # Tarball may have bin/ollama, usr/bin/ollama, or a single top-level dir
        if [ -f "$OLLAMA_INSTALL_DIR/bin/ollama" ]; then
          chmod +x "$OLLAMA_INSTALL_DIR/bin/ollama"
        elif [ -f "$OLLAMA_INSTALL_DIR/usr/bin/ollama" ]; then
          chmod +x "$OLLAMA_INSTALL_DIR/usr/bin/ollama"
        else
          FOUND=$(find "$OLLAMA_INSTALL_DIR" -maxdepth 4 -type f -name ollama 2>/dev/null | head -1)
          if [ -n "$FOUND" ]; then
            chmod +x "$FOUND"
            mkdir -p "$OLLAMA_INSTALL_DIR/bin"
            cp "$FOUND" "$OLLAMA_INSTALL_DIR/bin/ollama"
          fi
        fi
        if [ -x "$OLLAMA_INSTALL_DIR/bin/ollama" ] || [ -x "$OLLAMA_INSTALL_DIR/usr/bin/ollama" ]; then
          writeLine "  [OK] Ollama installed into module folder: $OLLAMA_INSTALL_DIR" "green"
        else
          writeLine "  [WARN] Extract may have failed; ollama binary not found. Install manually from https://ollama.com" "yellow"
        fi
      else
        writeLine "  [WARN] Download or extract failed. Install Ollama manually from https://ollama.com and ensure it is in PATH." "yellow"
      fi
      cd "$MODULE_DIR"
    fi
  fi
fi

# PATH and OLLAMA_MODELS for the rest of this script (and for runtime if module starts ollama)
export OLLAMA_MODELS="$OLLAMA_MODELS_DIR"
if [ -d "$OLLAMA_INSTALL_DIR/bin" ]; then
  export PATH="$OLLAMA_INSTALL_DIR/bin:$PATH"
fi
if [ -d "$OLLAMA_INSTALL_DIR/usr/bin" ]; then
  export PATH="$OLLAMA_INSTALL_DIR/usr/bin:$PATH"
fi
export PATH="/usr/local/bin:$PATH"

OLLAMA_CMD=$(ollama_bin)
if [ -z "$OLLAMA_CMD" ]; then
  writeLine "  [FAIL] Ollama binary not found (module dir or PATH)." "red"
  writeLine "  Install from https://ollama.com or ensure module install completed. Continuing with Python deps." "yellow"
  writeLine "Ollama MultiModal LLM by OmegaIT module install complete." "green"
  exit 0
fi

writeLine "  [OK] Using Ollama: $OLLAMA_CMD" "green"

# 2. Start Ollama if not already running (use module's binary and models dir)
if ! $OLLAMA_CMD list &>/dev/null; then
  if [ "$(uname -s)" = "Linux" ]; then
    writeLine "  Starting Ollama from module folder (models in $OLLAMA_MODELS)..." "cyan"
    mkdir -p "$OLLAMA_MODELS_DIR"
    nohup $OLLAMA_CMD serve >/tmp/ollama-serve.log 2>&1 &
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
      if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:11434/api/tags 2>/dev/null | grep -q 200; then
        break
      fi
      sleep 1
    done
    if $OLLAMA_CMD list &>/dev/null; then
      writeLine "  [OK] Ollama is running." "green"
    else
      writeLine "  [WARN] Ollama may still be starting. If pull fails, start it manually: OLLAMA_MODELS=$OLLAMA_MODELS $OLLAMA_CMD serve" "yellow"
    fi
  else
    writeLine "  [WARN] Ollama not responding. Start the Ollama app and ensure it is running." "yellow"
    writeLine "  Set OLLAMA_MODELS=$OLLAMA_MODELS if using the module's install." "yellow"
    writeLine "Ollama MultiModal LLM by OmegaIT module install complete." "green"
    exit 0
  fi
fi

if ! $OLLAMA_CMD list &>/dev/null; then
  writeLine "  [WARN] Ollama is not responding. Start with: OLLAMA_MODELS=$OLLAMA_MODELS $OLLAMA_CMD serve" "yellow"
  writeLine "Ollama MultiModal LLM by OmegaIT module install complete." "green"
  exit 0
fi

writeLine "  [OK] Ollama is running." "green"

# 3. Pull required Ollama models
writeLine "Pulling Ollama model: moondream (vision, for images)..." "cyan"
if $OLLAMA_CMD pull moondream; then
  writeLine "Moondream model ready." "green"
else
  writeLine "Could not pull moondream. Run 'ollama pull moondream' manually (with OLLAMA_MODELS=$OLLAMA_MODELS if using module install)." "yellow"
fi

writeLine "Pulling Ollama model: llama3.2 (for video summary)..." "cyan"
if $OLLAMA_CMD pull llama3.2; then
  writeLine "Llama3.2 model ready (video analysis)." "green"
else
  writeLine "Could not pull llama3.2. For video analysis run 'ollama pull llama3.2' manually." "yellow"
fi

# 4. Python dependencies
REQUIREMENTS="$MODULE_DIR/requirements.txt"
if [ -f "$REQUIREMENTS" ]; then
  writeLine "Installing Python dependencies (CodeProject.AI SDK, ollama, Pillow, etc.)..." "cyan"
  PIP_OK=0
  if [ -n "${venvPythonCmdPath:-}" ] && [ -x "$venvPythonCmdPath" ]; then
    "$venvPythonCmdPath" -m pip install -r "$REQUIREMENTS" && PIP_OK=1
  elif [ -n "${virtualEnvDirPath:-}" ] && [ -f "$virtualEnvDirPath/bin/pip" ]; then
    "$virtualEnvDirPath/bin/pip" install -r "$REQUIREMENTS" && PIP_OK=1
  elif [ -f "$MODULE_DIR/bin/pip" ]; then
    "$MODULE_DIR/bin/pip" install -r "$REQUIREMENTS" && PIP_OK=1
  elif [ -f "$MODULE_DIR/venv/bin/pip" ]; then
    "$MODULE_DIR/venv/bin/pip" install -r "$REQUIREMENTS" && PIP_OK=1
  else
    VENV_PIP=""
    for candidate in "$MODULE_DIR/bin/ubuntu/python310/venv/bin/pip" \
                     "$MODULE_DIR/bin/linux/python310/venv/bin/pip"; do
      if [ -f "$candidate" ]; then
        VENV_PIP="$candidate"
        break
      fi
    done
    if [ -z "$VENV_PIP" ] && [ -d "$MODULE_DIR/bin" ]; then
      VENV_PIP="$(find "$MODULE_DIR/bin" -path '*/venv/bin/pip' -type f 2>/dev/null | head -1)"
    fi
    if [ -n "$VENV_PIP" ] && [ -f "$VENV_PIP" ]; then
      "$VENV_PIP" install -r "$REQUIREMENTS" && PIP_OK=1
    else
      python3 -m pip install -r "$REQUIREMENTS" && PIP_OK=1
    fi
  fi
  if [ "$PIP_OK" = "1" ]; then
    writeLine "Python dependencies installed." "green"
  else
    writeLine "Warning: pip install failed. Module may not start until dependencies are installed." "yellow"
  fi
fi

writeLine "Ollama MultiModal LLM by OmegaIT module install complete." "green"
writeLine "  Ollama binary: $OLLAMA_INSTALL_DIR (models: $OLLAMA_MODELS). At runtime, start Ollama with: OLLAMA_MODELS=$OLLAMA_MODELS $OLLAMA_CMD serve" "cyan"
exit 0
