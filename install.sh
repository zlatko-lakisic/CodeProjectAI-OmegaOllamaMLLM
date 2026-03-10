# Installation script for Ollama MultiModal LLM by OmegaIT
# Called from CodeProject.AI setup with first argument "install"

if [ "$1" != "install" ]; then
  echo "This script is only called from CodeProject.AI setup.sh"
  exit 0
fi

writeLine "Checking prerequisites for Ollama MultiModal LLM by OmegaIT..." "cyan"

# 1. Check Ollama is in PATH
if ! command -v ollama &>/dev/null; then
  writeLine "  [FAIL] Ollama not found in PATH." "red"
  writeLine "  This module requires Ollama. Install from https://ollama.com and add it to PATH, then re-run setup." "yellow"
  writeLine "  Continuing with Python dependencies; the module will not work until Ollama is installed." "yellow"
  writeLine "Ollama MultiModal LLM by OmegaIT module install complete." "green"
  exit 0
fi

writeLine "  [OK] Ollama found in PATH." "green"

# 2. Check Ollama is running and reachable
if ! ollama list &>/dev/null; then
  writeLine "  [WARN] Ollama is in PATH but not responding. Start the Ollama app and ensure it is running." "yellow"
  writeLine "  After Ollama is running, run 'ollama pull moondream' manually." "yellow"
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

writeLine "Ollama MultiModal LLM by OmegaIT module install complete." "green"
exit 0
