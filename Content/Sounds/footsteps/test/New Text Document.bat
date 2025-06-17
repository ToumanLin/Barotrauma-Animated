@echo off
setlocal

echo Converting all .wav files to .ogg...
echo.

REM Convert all .wav files in the current directory to .ogg, then delete the original .wav
for %%F in (*.wav) do (
    echo Found file: %%F
    ffmpeg -y -i "%%F" "%%~nF.ogg"
    if exist "%%~nF.ogg" del "%%F"
)

echo.
echo All files processed.
pause
