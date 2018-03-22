'Option Explicit
Dim strError, cmdStr, objShell, objFSO, objReadFile, varFailedCount, strLine

Set objShell = Wscript.CreateObject("Wscript.Shell")

cmdStr = "%comspec% /c dcdiag /skip:SystemLog > dcdiagreport.txt"
objShell.run cmdStr, 1, true

Set objFSO = CreateObject("Scripting.FileSystemObject")
Set objReadFile = objFSO.OpenTextFile("dcdiagreport.txt", 1, False)
varFailedCount=0
Do Until objReadFile.AtEndOfStream
strLine = objReadFile.ReadLine
If InStr(strLine, "failed") Then
varFailedCount = varFailedCount + 1
strError = strError & strLine
End If
Loop

objReadFile.Close
objFSO.DeleteFile "dcdiagreport.txt"

Set objFSO = Nothing
Set objShell = Nothing

If Not strError = "" Then
wscript.echo strError
wscript.quit(2001)
Else
wscript.echo "No errors found"
wscript.quit(0)
End If
