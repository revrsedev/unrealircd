echo on

rem Temporarily hardcoded:
set TARGET=Visual Studio 2019
set SHORTNAME=vs2019

rem Initialize Visual Studio variables
if "%TARGET%" == "Visual Studio 2017" call "C:\Program Files (x86)\Microsoft Visual Studio\2017\Community\VC\Auxiliary\Build\vcvars64.bat"
if "%TARGET%" == "Visual Studio 2019" call "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat"

rem Installing tools
rem only for appveyor:
rem cinst unrar -y
rem cinst unzip -y
rem cinst innosetup -y

rem Installing UnrealIRCd dependencies
cd \projects
mkdir unrealircd-6-libs
cd unrealircd-6-libs
curl -fsS -o unrealircd-libraries-6-devel.zip https://www.unrealircd.org/files/dev/win/libs/unrealircd-libraries-6-devel.zip
unzip unrealircd-libraries-6-devel.zip
copy dlltool.exe \users\user\worker\unreal6-w10\build /y

rem for appveyor, use: cd \projects\unrealircd
cd \users\user\worker\unreal6-w10\build

rem Install 'unrealircd-tests'
cd ..
rd /q/s unrealircd-tests
rem Commented out due to private test repo (temporarily)
rem git clone https://github.com/unrealircd/unrealircd-tests.git
SET GIT_SSH_COMMAND=ssh -i ~/.ssh/unrealircd_tests_next.key -oIdentitiesOnly=yes
git clone -q --branch unreal60 git@github.com:/syzop/unrealircd-tests-next.git unrealircd-tests
if %ERRORLEVEL% NEQ 0 EXIT /B 1
cd build

rem Now the actual build
call extras\build-tests\windows\compilecmd\%SHORTNAME%.bat

rem The above command will fail, due to missing symbol file
rem However the symbol file can only be generated after the above command
rem So... we create the symbolfile...
nmake -f makefile.windows SYMBOLFILE

rem And we re-run the exact same command:
call extras\build-tests\windows\compilecmd\%SHORTNAME%.bat
if %ERRORLEVEL% NEQ 0 EXIT /B 1

rem Compile dependencies for unrealircd-tests -- this doesn't belong here though..
copy ..\unrealircd-tests\serverconfig\unrealircd\modules\fakereputation.c src\modules\third /Y
call extras\build-tests\windows\compilecmd\%SHORTNAME%.bat CUSTOMMODULE MODULEFILE=fakereputation
if %ERRORLEVEL% NEQ 0 EXIT /B 1

rem Convert c:\dev to c:\projects\unrealircd-6-libs
rem TODO: should use environment variable in innosetup script?
sed -i "s/c:\\dev\\unrealircd-6-libs/c:\\projects\\unrealircd-6-libs/gi" src\windows\unrealinst.iss

rem Build installer file
"c:\Program Files (x86)\Inno Setup 5\iscc.exe" /Q- src\windows\unrealinst.iss
if %ERRORLEVEL% NEQ 0 EXIT /B 1

rem Show some proof
ren mysetup.exe unrealircd-dev-build.exe
dir unrealircd-dev-build.exe
sha256sum unrealircd-dev-build.exe

rem Kill any old instances, just to be sure
taskkill -im unrealircd.exe -f
sleep 2
rem Just a safety measure so we don't end up testing
rem some old version...
del "C:\Program Files\UnrealIRCd 6\bin\unrealircd.exe"

echo Running installer...
start /WAIT unrealircd-dev-build.exe /VERYSILENT /LOG=setup.log
if %ERRORLEVEL% NEQ 0 goto installerfailed

rem Upload artifact
rem appveyor PushArtifact unrealircd-dev-build.exe
rem if %ERRORLEVEL% NEQ 0 EXIT /B 1

cd ..\unrealircd-tests
dir

rem All tests except db:
"C:\Program Files\Git\bin\bash.exe" ./runwin
if %ERRORLEVEL% NEQ 0 EXIT /B 1

rem Test unencrypted db's:
"C:\Program Files\Git\bin\bash.exe" ./runwin -boot tests/db/writing/*
if %ERRORLEVEL% NEQ 0 EXIT /B 1
"C:\Program Files\Git\bin\bash.exe" ./runwin -keepdbs -boot tests/db/reading/*
if %ERRORLEVEL% NEQ 0 EXIT /B 1

rem Test encrypted db's:
"C:\Program Files\Git\bin\bash.exe" ./runwin -include db_crypted.conf -boot tests/db/writing/*
if %ERRORLEVEL% NEQ 0 EXIT /B 1
"C:\Program Files\Git\bin\bash.exe" ./runwin -include db_crypted.conf -keepdbs -boot tests/db/reading/*
if %ERRORLEVEL% NEQ 0 EXIT /B 1

goto end



:installerfailed
type setup.log
echo INSTALLATION FAILED
EXIT /B 1

:end
