@echo off
rem Builds bin\Clawd.exe using the C# compiler that ships with Windows.
rem Nothing to install: no SDK, no runtime, no packages.
setlocal
set FW=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319
set WPF=%FW%\WPF

if not exist "%FW%\csc.exe" (
  echo Could not find the .NET Framework compiler at %FW%
  exit /b 1
)
if not exist "%~dp0bin" mkdir "%~dp0bin"

"%FW%\csc.exe" /nologo /target:winexe /platform:x64 /optimize+ /nowarn:0618 ^
  /out:"%~dp0bin\Clawd.exe" ^
  /win32icon:"%~dp0assets\clawd.ico" ^
  /r:System.dll /r:System.Core.dll /r:System.Xaml.dll ^
  /r:System.Drawing.dll /r:System.Windows.Forms.dll ^
  /r:"%WPF%\PresentationCore.dll" /r:"%WPF%\PresentationFramework.dll" /r:"%WPF%\WindowsBase.dll" ^
  "%~dp0src\*.cs"

if errorlevel 1 (
  echo.
  echo BUILD FAILED
  exit /b 1
)
echo Built bin\Clawd.exe
