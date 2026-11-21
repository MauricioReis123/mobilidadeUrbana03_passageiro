@echo off
setlocal

set "TARGET_DIR=mobilidade-urbana-03/passageiro"
set "WF_DIR=.github\workflows"
set "WF_FILE=%WF_DIR%\main.yml"
set "TMP_FILE=%temp%\flutter_main_yml_temp.txt"

echo ==================================================
echo Atualizando workflow Flutter para: %TARGET_DIR%
echo ==================================================

git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    echo [ERRO] Esta pasta nao e um repositorio Git valido.
    echo Coloque este .bat na pasta raiz do repositorio e tente novamente.
    pause
    exit /b 1
)

if not exist "%WF_DIR%" mkdir "%WF_DIR%"

if exist "%TMP_FILE%" del "%TMP_FILE%"

echo name: Build Flutter APK>>"%TMP_FILE%"
echo.>>"%TMP_FILE%"
echo on:>>"%TMP_FILE%"
echo workflow_dispatch:>>"%TMP_FILE%"
echo.>>"%TMP_FILE%"
echo jobs:>>"%TMP_FILE%"
echo build_android:>>"%TMP_FILE%"
echo name: Compilar APK Android>>"%TMP_FILE%"
echo runs-on: ubuntu-latest>>"%TMP_FILE%"
echo defaults:>>"%TMP_FILE%"
echo run:>>"%TMP_FILE%"
echo working-directory: %TARGET_DIR%>>"%TMP_FILE%"
echo.>>"%TMP_FILE%"
echo steps:>>"%TMP_FILE%"
echo - name: Baixar codigo do repositorio>>"%TMP_FILE%"
echo uses: actions/checkout@v4>>"%TMP_FILE%"
echo.>>"%TMP_FILE%"
echo - name: Configurar Java 17>>"%TMP_FILE%"
echo uses: actions/setup-java@v4>>"%TMP_FILE%"
echo with:>>"%TMP_FILE%"
echo distribution: 'temurin'>>"%TMP_FILE%"
echo java-version: '17'>>"%TMP_FILE%"
echo.>>"%TMP_FILE%"
echo - name: Configurar Flutter>>"%TMP_FILE%"
echo uses: subosito/flutter-action@v2>>"%TMP_FILE%"
echo with:>>"%TMP_FILE%"
echo channel: 'stable'>>"%TMP_FILE%"
echo cache: true>>"%TMP_FILE%"
echo.>>"%TMP_FILE%"
echo - name: Instalar dependencias>>"%TMP_FILE%"
echo run: flutter pub get>>"%TMP_FILE%"
echo.>>"%TMP_FILE%"
echo - name: Gerar APK Release>>"%TMP_FILE%"
echo run: flutter build apk --release>>"%TMP_FILE%"
echo.>>"%TMP_FILE%"
echo - name: Disponibilizar APK para download>>"%TMP_FILE%"
echo uses: actions/upload-artifact@v4>>"%TMP_FILE%"
echo with:>>"%TMP_FILE%"
echo name: app-release-apk>>"%TMP_FILE%"
echo path: %TARGET_DIR%/build/app/outputs/flutter-apk/app-release.apk>>"%TMP_FILE%"

copy /y "%TMP_FILE%" "%WF_FILE%" >nul
if errorlevel 1 (
    echo [ERRO] Falha ao gravar %WF_FILE%.
    pause
    exit /b 1
)

if exist "%TMP_FILE%" del "%TMP_FILE%"

echo [OK] Arquivo %WF_FILE% sobrescrito com sucesso.

git add "%WF_FILE%"
if errorlevel 1 (
    echo [ERRO] Falha no git add.
    pause
    exit /b 1
)

git diff --cached --quiet
if not errorlevel 1 (
    echo [AVISO] Nenhuma diferenca nova detectada em %WF_FILE%.
) else (
    git commit -m "Atualiza .github/workflows/main.yml para %TARGET_DIR%"
    if errorlevel 1 (
        echo [ERRO] Falha no git commit.
        pause
        exit /b 1
    )
)

echo Enviando alteracoes para o repositorio remoto...
git push
if errorlevel 1 (
    echo [ERRO] Falha no git push. Verifique sua autenticacao ou branch remota.
    pause
    exit /b 1
)

echo ==================================================
echo [SUCESSO] Workflow atualizado e enviado!
echo Agora va na aba Actions no GitHub e rode o workflow.
echo ==================================================
pause
exit /b 0

