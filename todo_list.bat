@echo off

set searchFiles=*.jai

echo -----
echo TODO LIST:
findstr -s -n -i -l "TODO:" %searchFiles%
echo -----
echo.
echo -----
echo BUG LIST:
findstr -s -n -i -l "BUG:" %searchFiles%
echo -----
