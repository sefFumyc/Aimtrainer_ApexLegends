@echo off
rem 游戏入口：双击进游戏。优先跑已导出的独立 exe，没有再用本机引擎窗口版跑主场景。
rem 想看引擎日志可改用同目录的 Godot_v4.7.2-stable_win64_console.exe。
rem 注意：本文件必须保存为 ANSI（GBK）编码——cmd 按 GBK 解析批处理，UTF-8 中文会乱码报错。
set EXE=%~dp0build\aim-trainer.exe
if exist "%EXE%" (
    start "" "%EXE%"
    exit /b 0
)
set ENGINE=%~dp0..\..\godot\4.7.2-stable\Godot_v4.7.2-stable_win64.exe
if not exist "%ENGINE%" (
    echo 找不到引擎：%ENGINE%
    pause
    exit /b 1
)
start "" "%ENGINE%" --path "%~dp0."
