@echo off
chcp 65001 >nul
rem 游戏入口（票 05 第 3 项兜底方案）：不开编辑器，用本机引擎窗口版直接跑主场景。
rem 独立 exe 等导出模板装好后按 export_presets.cfg 出包（build/ 目录）。
rem 想看引擎日志可改用同目录的 Godot_v4.7.2-stable_win64_console.exe。
set ENGINE=%~dp0..\..\godot\4.7.2-stable\Godot_v4.7.2-stable_win64.exe
if not exist "%ENGINE%" (
    echo 找不到引擎：%ENGINE%
    pause
    exit /b 1
)
start "" "%ENGINE%" --path "%~dp0."
