@echo off
title AutAnalysis Dev Tools
color 0B

:menu
cls
echo ========================================================
echo               AutAnalysis Dev Tools Menu
echo ========================================================
echo.
echo  [1] Avvia Backend (Docker Compose Up)
echo  [2] Ferma Backend (Docker Compose Down)
echo  [3] Ricostruisci Backend (Docker Compose Build)
echo.
echo  [4] Avvia Frontend (Flutter su Chrome)
echo  [5] Genera Frontend (Flutter APK)
echo.
echo  [6] Push modifiche su GitHub (Git Add, Commit, Push)
echo.
echo  [0] Esci
echo.
echo ========================================================
set /p choice="Scegli un'opzione [0-6]: "

if "%choice%"=="1" goto start_backend
if "%choice%"=="2" goto stop_backend
if "%choice%"=="3" goto build_backend
if "%choice%"=="4" goto start_flutter
if "%choice%"=="5" goto build_apk
if "%choice%"=="6" goto git_push
if "%choice%"=="0" goto exit

echo Scelta non valida, riprova.
pause
goto menu

:start_backend
echo Avvio dei container Docker...
docker-compose up -d
pause
goto menu

:stop_backend
echo Chiusura dei container Docker...
docker-compose down
pause
goto menu

:build_backend
echo Ricostruzione dell'immagine Docker backend...
docker-compose up -d --build
pause
goto menu

:start_flutter
echo Avvio del frontend su Chrome...
cd frontend
:: Uso il percorso assoluto che mi hai fornito
"C:\Users\gianvito.bleve\OneDrive - Banca Mediolanum SPA\Documenti\Programmi\flutter\bin\flutter.bat" run -d chrome
cd ..
pause
goto menu

:build_apk
echo Generazione APK in corso...
cd frontend
"C:\Users\gianvito.bleve\OneDrive - Banca Mediolanum SPA\Documenti\Programmi\flutter\bin\flutter.bat" build apk
cd ..
pause
goto menu

:git_push
echo.
:: 1. Pulisco la variabile per evitare memorie da esecuzioni precedenti
set "commit_msg=" 

:: 2. Chiedo l'input all'utente in modo sicuro
set /p "commit_msg=Inserisci il messaggio di commit (invio per default): "

:: 3. Se l'utente preme solo invio, assegno "Update" senza usare doppie virgolette problematiche
if not defined commit_msg set "commit_msg=Update"

echo.
echo Preparazione del commit...
git add .
git commit -m "%commit_msg%"

:: 4. Il parametro -u (upstream) crea e mantiene automaticamente il ponte verso GitHub
git push -u origin main

echo.
echo Push completato con successo!
pause
goto menu

:exit
exit
