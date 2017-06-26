@echo off
REM Wrapper script to perform a local run of CI assuming everything is already setup.
REM This is set for the CI servers. The production servers should be pre-configured with these
REM variables already - the C drive is the system drive, D is a fast SSD.

set SOURCES_DRIVE=c
set SOURCES_SUBDIR=gopath
set TESTRUN_DRIVE=d
set TESTRUN_SUBDIR=CI

powershell .\executeCI.ps1
