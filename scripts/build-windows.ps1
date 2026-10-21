$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
  throw 'Node.js 22.12+ and npm are required.'
}

npm install
npm run build
npx electron-builder --win nsis --x64 --publish never
Write-Host "Check the release folder for Remim-Setup-0.1.0-x64.exe"
