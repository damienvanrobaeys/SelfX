Clear-RecycleBin -confirm:$false -force
Get-ChildItem "$env:temp\*" -recurse | remove-item -recurse -force -ea silentlycontinue
