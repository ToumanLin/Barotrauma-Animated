@echo off
setlocal

:: Get the directory where this batch script is located (i.e., 00_RELEASE)
set "RELEASE_DIR=%~dp0"

:: Get the path to the main mod directory (Barotrauma-Animated)
:: This assumes Barotrauma-Animated and 00_RELEASE are siblings under LocalMods
set "LOCALMODS_DIR=%RELEASE_DIR%.."
set "MOD_ROOT_DIR=%LOCALMODS_DIR%\Barotrauma-Animated"

:: Get the path to the Repo folder within the mod directory
set "REPO_DIR=%MOD_ROOT_DIR%\Repo"

:: Check if the Python script exists
if not exist "%REPO_DIR%\release.py" (
    echo ERROR: release.py not found at "%REPO_DIR%\release.py"
    echo Please ensure the file structure is correct.
    pause
    exit /b 1
)

echo.
echo Launching Barotrauma Mod Release Process...
echo Release Output Directory: "%RELEASE_DIR%"
echo Mod Source Directory: "%MOD_ROOT_DIR%"
echo.

:: Execute the Python release script
:: It will handle all the cleaning, generating, copying, and modifying.
:: It's crucial that release.py's internal logic expects to be run from the
:: desired output directory (which is %RELEASE_DIR% here).
pushd "%RELEASE_DIR%"
python "%REPO_DIR%\release.py"
popd

echo.
echo Release process finished.
pause