@ECHO OFF
:: Ping and IP address or FQDN from
:: a workstation and return a result
:: to MaxRM as a script check.
::
:: Set address to be pinged on command line.
::
:: Parsec Computer Corp.
:: Created by:  Van Donley on 12/15/2016
:: Updated by:  Van Donley on 08/02/2017
:: Set address to be pinged.
IF [%1]==[] SET _ADDRESS=www.google.com
IF NOT [%1]==[] SET _ADDRESS=%1
:: Ping the address
PING %_ADDRESS% && @ECHO %_ADDRESS% is online. || SET ERRORLEVEL=1001 && @ECHO Communication problem with %_ADDRESS%
EXIT %ERRORLEVEL%