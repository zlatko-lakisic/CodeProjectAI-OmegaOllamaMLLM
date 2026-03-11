# Installation script for Ollama MultiModal LLM by OmegaIT
# Called from CodeProject.AI setup with first argument "install"

if [ "$1" != "install" ]; then
  echo "This script is only called from CodeProject.AI setup.sh"
  exit 0
fi

writeLine "Checking prerequisites for Ollama MultiModal LLM by OmegaIT..." "cyan"

# Ensure /usr/local/bin is in PATH (Ollama installs there on Linux)
export PATH="/usr/local/bin:$PATH"

# 1. Check Ollama is in PATH; on Linux, try to install if missing
if ! command -v ollama &>/dev/null; then
  if [ "$(uname -s)" = "Linux" ]; then
    writeLine "  Ollama not found in PATH. Attempting to install Ollama for Linux..." "yellow"
    if command -v curl &>/dev/null; then
      # Install zstd if missing (required by recent Ollama install script for extraction)
      if ! command -v zstd &>/dev/null; then
        writeLine "  Installing zstd for Ollama installer..." "cyan"
        if command -v apt-get &>/dev/null; then
          apt-get update -qq 2>/dev/null || true
          apt-get install -y -qq zstd 2>/dev/null || true
        fi
      fi
      if curl -fsSL https://ollama.com/install.sh | sh; then
        export PATH="/usr/local/bin:$PATH"
        if command -v ollama &>/dev/null; then
          writeLine "  [OK] Ollama installed successfully." "green"
        else
          writeLine "  [WARN] Ollama install script ran but binary not in PATH. Add /usr/local/bin to PATH." "yellow"
        fi
      else
        writeLine "  [FAIL] Ollama install script failed. Install manually from https://ollama.com" "red"
        writeLine "  Continuing with Python dependencies; the module will not work until Ollama is installed." "yellow"
        writeLine "Ollama MultiModal LLM by OmegaIT module install complete." "green"
        exit 0
      fi
    else
      writeLine "  [FAIL] Ollama not found and curl is missing. Install curl and re-run, or install Ollama from https://ollama.com" "red"
      writeLine "  Continuing with Python dependencies; the module will not work until Ollama is installed." "yellow"
      writeLine "Ollama MultiModal LLM by OmegaIT module install complete." "green"
      exit 0
    fi
  else
    writeLine "  [FAIL] Ollama not found in PATH." "red"
    writeLine "  This module requires Ollama. Install from https://ollama.com and add it to PATH, then re-run setup." "yellow"
    writeLine "  Continuing with Python dependencies; the module will not work until Ollama is installed." "yellow"
    writeLine "Ollama MultiModal LLM by OmegaIT module install complete." "green"
    exit 0
  fi
fi

if ! command -v ollama &>/dev/null; then
  writeLine "  [FAIL] Ollama still not found in PATH after install attempt." "red"
  writeLine "  Continuing with Python dependencies; the module will not work until Ollama is installed." "yellow"
  writeLine "Ollama MultiModal LLM by OmegaIT module install complete." "green"
  exit 0
fi

writeLine "  [OK] Ollama found in PATH." "green"

# 2. Check Ollama is running and reachable (start it if we just installed on Linux)
if ! ollama list &>/dev/null; then
  if [ "$(uname -s)" = "Linux" ]; then
    writeLine "  Starting Ollama service in background..." "cyan"
    nohup ollama serve >/tmp/ollama-serve.log 2>&1 &
    OLLAMA_PID=$!
    # Wait for API to be ready (up to 30 seconds)
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
      if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:11434/api/tags 2>/dev/null | grep -q 200; then
        break
      fi
      sleep 1
    done
    if ollama list &>/dev/null; then
      writeLine "  [OK] Ollama is running." "green"
    else
      writeLine "  [WARN] Ollama may still be starting. If pull fails, start it manually (ollama serve) and run 'ollama pull moondream'." "yellow"
    fi
  else
    writeLine "  [WARN] Ollama is in PATH but not responding. Start the Ollama app and ensure it is running." "yellow"
    writeLine "  After Ollama is running, run 'ollama pull moondream' manually." "yellow"
    writeLine "Ollama MultiModal LLM by OmegaIT module install complete." "green"
    exit 0
  fi
fi

if ! ollama list &>/dev/null; then
  writeLine "  [WARN] Ollama is not responding. Start Ollama (e.g. 'ollama serve') and run 'ollama pull moondream' manually." "yellow"
  writeLine "Ollama MultiModal LLM by OmegaIT module install complete." "green"
  exit 0
fi

writeLine "  [OK] Ollama is running." "green"

# 3. Pull moondream model if not already present
writeLine "Pulling Ollama model: moondream (this may take a few minutes)..." "cyan"
if ollama pull moondream; then
  writeLine "Moondream model ready." "green"
else
  writeLine "Could not pull moondream. Run 'ollama pull moondream' manually." "yellow"
fi

# 4. Ensure Python dependencies are installed in the module venv (codeproject_ai_sdk, ollama, etc.)
MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
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
    # CodeProject.AI Docker/Linux uses bin/<os>/python<ver>/venv/bin (e.g. bin/ubuntu/python310/venv/bin/pip)
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
exit 0
