@echo off
setlocal EnableDelayedExpansion
REM Installation script for Ollama MultiModal LLM by OmegaIT
REM Called from CodeProject.AI setup with first argument "install"

if "%1" NEQ "install" (
  echo This script is only called from CodeProject.AI setup.bat
  goto :eof
)

REM Backwards compatibility
if "!utilsScript!" == "" if "!sdkScriptsDirPath!" NEQ "" set utilsScript=!sdkScriptsDirPath!\utils.bat

call "!utilsScript!" WriteLine "Checking prerequisites for Ollama MultiModal LLM by OmegaIT..." "cyan"

REM 1. Check Ollama is in PATH
where ollama >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
  call "!utilsScript!" WriteLine "  [FAIL] Ollama not found in PATH." "red"
  call "!utilsScript!" WriteLine "  This module requires Ollama. Install from https://ollama.com and add it to PATH, then re-run setup." "yellow"
  call "!utilsScript!" WriteLine "  Continuing with Python dependencies; the module will not work until Ollama is installed." "yellow"
  goto :pip_done
)

call "!utilsScript!" WriteLine "  [OK] Ollama found in PATH." "green"

REM 2. Check Ollama is running and reachable
ollama list >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
  call "!utilsScript!" WriteLine "  [WARN] Ollama is in PATH but not responding. Start the Ollama app and ensure it is running." "yellow"
  call "!utilsScript!" WriteLine "  After Ollama is running, run 'ollama pull moondream' manually." "yellow"
  goto :pip_done
)

call "!utilsScript!" WriteLine "  [OK] Ollama is running." "green"

REM 3. Pull moondream model if not already present
call "!utilsScript!" WriteLine "Pulling Ollama model: moondream (this may take a few minutes)..." "cyan"
ollama pull moondream
if !ERRORLEVEL! NEQ 0 (
  call "!utilsScript!" WriteLine "Could not pull moondream. Run 'ollama pull moondream' manually." "yellow"
) else (
  call "!utilsScript!" WriteLine "Moondream model ready." "green"
)

:pip_done
REM Python dependencies are installed automatically from requirements.txt by the setup lifecycle.
call "!utilsScript!" WriteLine "Ollama MultiModal LLM by OmegaIT module install complete." "green"
exit /b 0
