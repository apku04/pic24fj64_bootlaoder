# Bootloader Makefile
# Use build.ps1 for building or this Makefile with make

.DEFAULT_GOAL := all

all:
	powershell -NoProfile -ExecutionPolicy Bypass -File build.ps1

clean:
	powershell -NoProfile -ExecutionPolicy Bypass -File build.ps1 -Clean

.PHONY: all clean
