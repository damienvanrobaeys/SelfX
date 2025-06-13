$Get_Firefox_Process = gwmi win32_process | where {$_.Name -like "*firefox*"}
If($Get_Firefox_Process -ne $null)
	{
		$Get_Firefox_Process.Terminate() | out-null		
	}
	
$firefoxAppDataPath = "C:\users\$user\AppData\Local\Mozilla\Firefox\Profiles" 
If(Test-Path $firefoxAppDataPath)
{
    $possibleCachePaths = @('cache','cache2\entries','thumbnails','cookies.sqlite','webappsstore.sqlite','chromeappstore.sqlite')	
    $firefoxAppDataPath = (Get-ChildItem "C:\users\$user\AppData\Local\Mozilla\Firefox\Profiles" | Where-Object { $_.Name -match 'Default' }[0]).FullName 	
	ForEach($cachePath in $possibleCachePaths)
	{
		Remove-Item "$firefoxAppDataPath\$cachePath" -Force -Recurse
	}      
} 

