$Get_Chrome_Process = gwmi win32_process | where {$_.Name -like "*chrome*"}
If($Get_Chrome_Process -ne $null)
	{
		$Get_Chrome_Process.Terminate() | out-null		
	}
	
$chromeAppData = "C:\Users\$user\AppData\Local\Google\Chrome\User Data\Default" 
If(Test-Path $chromeAppData)
{
	$possibleCachePaths = @('Cache','Cache2\entries\','Cookies','History','Top Sites','VisitedLinks','Web Data','Media Cache','Cookies-Journal','ChromeDWriteFontCache')
	ForEach($cachePath in $possibleCachePaths)
	{
		Remove-Item "$chromeAppData\$cachePath" -Force -Recurse
	}      
} 
