# Run this in an elevated PowerShell (Run as Administrator)
icacls "D:\Games" /deny "ALL APPLICATION PACKAGES":(OI)(CI)(RX) "ALL RESTRICTED APPLICATION PACKAGES":(OI)(CI)(RX)
