@echo off
setlocal

:: Get the name of this script
set "SELF=%~nx0"
echo About to clean directory: "%CD%"
pause

if /I "%CD%"=="%windir%\System32" (
  echo ERROR: Running in %windir%\System32 is forbidden!
  pause
  exit /b 1
)

:: Clear all files except this .bat file
echo Cleaning current directory (excluding this script: %SELF%)...
for %%f in (*.*) do (
    if /I not "%%f"=="%SELF%" del /q "%%f"
)

:: Delete all subfolders
for /d %%d in (*) do rd /s /q "%%d"

:: Set source path
set "SOURCE=C:\Program Files (x86)\Steam\steamapps\common\Barotrauma\LocalMods\Barotrauma-Animated"

echo Generating item list…
python "%SOURCE%\00_GenerateItemList.py"

:: Copy folders
echo Copying folders...
xcopy "%SOURCE%\About" "About" /e /i /y
xcopy "%SOURCE%\Content" "Content" /e /i /y
xcopy "%SOURCE%\Subs" "Subs" /e /i /y

:: Copy file
echo Copying filelist.xml...
copy "%SOURCE%\filelist.xml" "filelist.xml" /y

:: Run the Python modifier
echo Modifying filelist.xml with Python…
python "%SOURCE%\00_modify_filelist.py" "filelist.xml"

echo Done.
pause