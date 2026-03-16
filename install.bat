@echo off
setlocal EnableDelayedExpansion
REM Installation script for Ollama MultiModal LLM by OmegaIT
REM Called from CodeProject.AI setup with first argument "install"
REM Installs Ollama into the module folder (per https://docs.ollama.com/windows standalone CLI)
REM so it persists when the module lives on a volume or custom path.

if "%1" NEQ "install" (
  echo This script is only called from CodeProject.AI setup.bat
  goto :eof
)

REM Backwards compatibility
if "!utilsScript!" == "" if "!sdkScriptsDirPath!" NEQ "" set utilsScript=!sdkScriptsDirPath!\utils.bat

REM Module dir and Ollama install path (same layout as install.sh)
set "MODULE_DIR=%~dp0"
if "%MODULE_DIR:~-1%"=="\" set "MODULE_DIR=%MODULE_DIR:~0,-1%"
if "!OLLAMA_INSTALL_DIR!"=="" set "OLLAMA_INSTALL_DIR=!MODULE_DIR!\ollama"
if "!OLLAMA_MODELS_DIR!"=="" set "OLLAMA_MODELS_DIR=!MODULE_DIR!\models"

call "!utilsScript!" WriteLine "Checking prerequisites for Ollama MultiModal LLM by OmegaIT..." "cyan"

REM 1. Install Ollama into module folder if not already present (Windows standalone CLI per docs.ollama.com/windows)
set "OLLAMA_EXE="
if exist "!OLLAMA_INSTALL_DIR!\ollama.exe" set "OLLAMA_EXE=!OLLAMA_INSTALL_DIR!\ollama.exe"
if "!OLLAMA_EXE!"=="" (
  REM Check for zip extract that put exe in a subfolder (e.g. ollama-windows-amd64\ollama.exe)
  for /d %%D in ("!OLLAMA_INSTALL_DIR!\*") do (
    if exist "%%D\ollama.exe" set "OLLAMA_EXE=%%D\ollama.exe"
  )
)
if "!OLLAMA_EXE!"=="" where ollama >nul 2>&1 && set "OLLAMA_EXE=ollama"

if "!OLLAMA_EXE!"=="" (
  REM Download and extract standalone CLI (ollama-windows-amd64.zip) into module folder
  call "!utilsScript!" WriteLine "  Ollama not found. Installing Ollama into module folder (standalone CLI)..." "yellow"
  set "OLLAMA_ZIP=!OLLAMA_INSTALL_DIR!\ollama-windows-amd64.zip"
  set "OLLAMA_URL=https://ollama.com/download/ollama-windows-amd64.zip"
  if not exist "!OLLAMA_INSTALL_DIR!" mkdir "!OLLAMA_INSTALL_DIR!"
  call "!utilsScript!" WriteLine "  Downloading !OLLAMA_URL! ..." "cyan"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '!OLLAMA_URL!' -OutFile '!OLLAMA_ZIP!' -UseBasicParsing } catch { exit 1 }"
  if !ERRORLEVEL! NEQ 0 (
    call "!utilsScript!" WriteLine "  [WARN] Download failed. Install Ollama from https://ollama.com and add to PATH." "yellow"
    goto :pip_done
  )
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Path '!OLLAMA_ZIP!' -DestinationPath '!OLLAMA_INSTALL_DIR!' -Force"
  if !ERRORLEVEL! NEQ 0 (
    call "!utilsScript!" WriteLine "  [WARN] Extract failed. Install Ollama from https://ollama.com." "yellow"
    goto :pip_done
  )
  del /q "!OLLAMA_ZIP!" 2>nul
  REM Zip may extract to subfolder (e.g. ollama-windows-amd64\); move contents up if ollama.exe not directly in OLLAMA_INSTALL_DIR
  if not exist "!OLLAMA_INSTALL_DIR!\ollama.exe" (
    for /d %%D in ("!OLLAMA_INSTALL_DIR!\*") do (
      if exist "%%D\ollama.exe" (
        xcopy "%%D\*" "!OLLAMA_INSTALL_DIR!\" /E /Y /Q >nul 2>&1
        rd /s /q "%%D" 2>nul
        goto :ollama_extract_done
      )
    )
  )
  :ollama_extract_done
  if exist "!OLLAMA_INSTALL_DIR!\ollama.exe" (
    set "OLLAMA_EXE=!OLLAMA_INSTALL_DIR!\ollama.exe"
    call "!utilsScript!" WriteLine "  [OK] Ollama installed into module folder: !OLLAMA_INSTALL_DIR!" "green"
  ) else (
    call "!utilsScript!" WriteLine "  [WARN] Extract did not produce ollama.exe. Install from https://ollama.com." "yellow"
    goto :pip_done
  )
) else (
  if "!OLLAMA_EXE!"=="ollama" (
    call "!utilsScript!" WriteLine "  [OK] Ollama found in PATH." "green"
  ) else (
    call "!utilsScript!" WriteLine "  [OK] Using Ollama from module folder: !OLLAMA_EXE!" "green"
  )
)

REM PATH and OLLAMA_MODELS for the rest of this script (and for runtime)
set "OLLAMA_MODELS=!OLLAMA_MODELS_DIR!"
set "PATH=!OLLAMA_INSTALL_DIR!;!PATH!"

REM 2. Check Ollama is running and reachable; start if we just installed
if "!OLLAMA_EXE!" NEQ "ollama" "!OLLAMA_EXE!" list >nul 2>&1
if "!OLLAMA_EXE!"=="ollama" ollama list >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
  call "!utilsScript!" WriteLine "  Starting Ollama from module folder (models in !OLLAMA_MODELS!)..." "cyan"
  if not exist "!OLLAMA_MODELS_DIR!" mkdir "!OLLAMA_MODELS_DIR!"
  if "!OLLAMA_EXE!" NEQ "ollama" (
    start /B "" "!OLLAMA_EXE!" serve
  ) else (
    start /B "" ollama serve
  )
  timeout /t 5 /nobreak >nul
  if "!OLLAMA_EXE!" NEQ "ollama" "!OLLAMA_EXE!" list >nul 2>&1
  if "!OLLAMA_EXE!"=="ollama" ollama list >nul 2>&1
  if !ERRORLEVEL! NEQ 0 (
    call "!utilsScript!" WriteLine "  [WARN] Ollama may still be starting. If pull fails, start manually: set OLLAMA_MODELS=!OLLAMA_MODELS! && \"!OLLAMA_EXE!\" serve" "yellow"
  ) else (
    call "!utilsScript!" WriteLine "  [OK] Ollama is running." "green"
  )
) else (
  call "!utilsScript!" WriteLine "  [OK] Ollama is running." "green"
)

if "!OLLAMA_EXE!" NEQ "ollama" "!OLLAMA_EXE!" list >nul 2>&1
if "!OLLAMA_EXE!"=="ollama" ollama list >nul 2>&1
if !ERRORLEVEL! NEQ 0 (
  call "!utilsScript!" WriteLine "  [WARN] Ollama is not responding. Start with: set OLLAMA_MODELS=!OLLAMA_MODELS! && \"!OLLAMA_EXE!\" serve" "yellow"
  goto :pip_done
)

REM 3. Pull required Ollama models
call "!utilsScript!" WriteLine "Pulling Ollama model: moondream (vision, for images)..." "cyan"
if "!OLLAMA_EXE!" NEQ "ollama" "!OLLAMA_EXE!" pull moondream
if "!OLLAMA_EXE!"=="ollama" ollama pull moondream
if !ERRORLEVEL! NEQ 0 (
  call "!utilsScript!" WriteLine "Could not pull moondream. Run 'ollama pull moondream' manually (set OLLAMA_MODELS=!OLLAMA_MODELS! if using module install)." "yellow"
) else (
  call "!utilsScript!" WriteLine "Moondream model ready." "green"
)

call "!utilsScript!" WriteLine "Pulling Ollama model: llama3.2 (for video summary)..." "cyan"
if "!OLLAMA_EXE!" NEQ "ollama" "!OLLAMA_EXE!" pull llama3.2
if "!OLLAMA_EXE!"=="ollama" ollama pull llama3.2
if !ERRORLEVEL! NEQ 0 (
  call "!utilsScript!" WriteLine "Could not pull llama3.2. For video analysis run 'ollama pull llama3.2' manually." "yellow"
) else (
  call "!utilsScript!" WriteLine "Llama3.2 model ready (video analysis)." "green"
)

:pip_done
REM Python dependencies are installed automatically from requirements.txt by the setup lifecycle.
call "!utilsScript!" WriteLine "Ollama MultiModal LLM by OmegaIT module install complete." "green"
call "!utilsScript!" WriteLine "  Ollama binary: !OLLAMA_INSTALL_DIR! (models: !OLLAMA_MODELS!). At runtime, start with: set OLLAMA_MODELS=!OLLAMA_MODELS! && \"!OLLAMA_EXE!\" serve" "cyan"
exit /b 0
